# Proposal: Phase 3 — Automatic Reference Counting (ARC)

> **Status: draft / plan.** Implementation not started. This is the
> implementation plan for Phase 3 of the [memory-management
> direction](memory-management.md): ARC for the heap values that genuinely
> escape, with the [effect kinds](../language-guide.md) deciding where counts go.

## Goal and scope

Give deterministic, dependency-free reclamation to the heap values that outlive
their scope, so long-running programs (servers above all) stop leaking — without
a tracing GC, without atomics, and without the user learning lifetimes.

**In scope:** the three heap-backed value families:

| Value | Representation today | Backing store |
|-------|----------------------|---------------|
| `String` | `xc_string_t { const char* data; size_t len }` | `data` buffer (malloc'd by `xc_str_copy`/`xc_string_concat`, **or** static `.rodata` for literals via `xc_string_from_cstr`) |
| arrays | `{ T* data; size_t len; size_t cap }` | `data` backing store (malloc'd) |
| boxed instances | `xc_<Class>_t*` (from `xc_new_<Class>`) | the instance (malloc'd; singletons live in static storage) |

**Out of scope (for v1):** reference cycles (precluded in practice by the
immutable/acyclic value model; covered by a `weak` qualifier where a back-edge is
unavoidable — leak-don't-crash if one slips through), and small value structs
(compounds passed by value keep pure copy semantics, no count).

## The central challenge: heap vs static vs arena

`xc_string_t` carries no tag. Given a `const char* data`, `release` cannot tell
whether it points at a malloc'd buffer (free it at rc 0), a string **literal** in
`.rodata` (must never free), or a **per-thread arena** block (freed en masse at
thread exit — `release` must not touch it). Solving this *correctly* is the gate
for everything else. Three options:

- **(A) Magic header, heuristic discrimination.** Prepend
  `struct { uint64_t magic; uint32_t rc; }` to every malloc'd buffer and point
  `.data` past it. `release(data)` reads `((hdr*)data)[-1]`; if `magic` matches,
  it's managed — otherwise (a literal) no-op. *Pro:* literals stay zero-cost in
  `.rodata`. *Con:* reading `data[-sizeof(hdr)]` for a literal is an out-of-bounds
  read (usually same page, but can fault for a literal at a page boundary), and a
  64-bit magic is a probabilistic, not total, guarantee.

- **(B) Everything managed; intern literals (recommended).** Make the invariant
  *every `xc_string_t.data` points just past a header* — no exceptions. Literals
  are interned once into a permanent block with an **immortal** rc sentinel
  (`rc = UINT32_MAX`), cached by literal identity so a literal in a loop allocates
  zero times after the first. `retain`/`release` always find a valid header; no
  OOB reads, no magic guessing; immortal blocks ignore both ops. *Pro:* sound and
  simple to reason about. *Con:* one-time intern allocation per distinct literal
  and a small intern table; codegen must route literal construction through
  `xc_str_lit(...)`.

- **(C) Tag the fat pointer.** Add a field/bit to `xc_string_t`. *Rejected:* it
  changes the struct layout, which ripples through essentially all generated C and
  perturbs the self-host fixpoint output — maximum churn for the same result as
  (B).

**Recommendation: (B).** Keep `xc_string_t` at `{data,len}` (no layout change),
put the count in a header before the buffer, and make literals and arena blocks
**immortal** so the same `retain`/`release` path is total and branch-light. Arena
allocations (`xc_arena_alloc`) get the immortal sentinel too, so ARC and the
existing per-thread arenas compose: arena blocks are reclaimed by arena teardown
and ARC never double-frees them.

The same header scheme applies to array backing stores and boxed instances
(singletons get the immortal sentinel, since they are process-lifetime by
design).

## Runtime additions

```c
/* Prepended to every managed heap block. */
typedef struct { uint32_t rc; uint32_t flags; } xc_rc_hdr;   /* flags: IMMORTAL */

void* xc_rc_alloc(size_t n);          /* malloc(hdr+n), rc=1, return past hdr  */
void* xc_rc_immortal(size_t n);       /* rc=IMMORTAL (literals, arena, singleton) */
void  xc_retain(const void* p);       /* ++rc unless immortal                  */
void  xc_release(const void* p);      /* --rc; free(block) at 0 unless immortal */
```

- `xc_str_copy`, `xc_string_concat`, `split`, etc. switch from `malloc` to
  `xc_rc_alloc`.
- Array append/grow helpers (in `xc_helpers.c`) allocate backing stores via
  `xc_rc_alloc`.
- `xc_new_<Class>` allocates via `xc_rc_alloc`; the singleton path uses immortal.
- `xc_arena_alloc` blocks are immortal (freed by the arena).
- Counts are **non-atomic** — safe because ownership never crosses the
  share-nothing thread boundary (channel sends copy).

## Where counts go — driven by the effect kinds

This is where Phase 2 pays off. The kind of a function already states how values
flow through it, so insertion is a per-kind rule, not a global dataflow analysis:

| Construct | Rule |
|-----------|------|
| `mapper` / `predicate` / `projector` params | **borrowed** — no retain on entry, no release of params (purity, now enforced, guarantees they can't escape) |
| pure-fn return | the value is freshly owned by the caller (+1 already from its `xc_rc_alloc`); **move** out, no extra retain |
| `creator` / `producer` return | owned (+1); caller takes ownership |
| `consumer` params | **consumed** — released at end of body unless stored |
| `action` params captured into `self`/state | **retained** (stored owned) |
| `let x = <owned expr>` | x owns it; **release at scope exit** unless moved/returned |
| rebinding `x = <expr>` | release old value, retain/own new |
| store into field / array / struct | **retain** |
| pass owned value to a borrowing param | no count change |
| pass owned value to a consuming/storing param | **move** (no retain) or **retain** if still used afterward |

Net effect: the overwhelmingly common pure path touches **no counts at all**
(borrows), and retains appear only at the handful of kind boundaries where
ownership actually moves — exactly the proposal's thesis.

## `own` / `move` / `dup` / `weak`

Already in the grammar (lexed, currently ignored). Give them meaning as count
control:

- `move x` — transfer ownership; source is dead afterward, no retain, no release
  of the source.
- `dup x` — force an independent owned copy (retain, or deep copy for arrays when
  needed).
- `own T` — a binding/param that takes ownership (so a `consumer`/`action` can
  declare it stores the value).
- `weak T` — a non-owning reference that does not retain; the back-edge escape
  hatch for the rare cycle. Reading a `weak` yields a normal borrow.

These are optimisation/▸correctness hints layered on top of the automatic rules;
none are required for the baseline to be correct.

## Phased rollout (each phase gated on a green self-host)

The self-hosting compiler is both the deliverable and the torture test: it is a
large Ξ program, so if retain/release is wrong it will crash or leak while
compiling itself. Roll out in slices that each keep `selfhost.sh` byte-identical
**and** runnable, under AddressSanitizer.

- **3a — Infrastructure, no frees.** Add the header + `xc_rc_alloc`/`retain`/
  `release`/immortal; route all allocations through them; intern literals;
  mark arena/singleton blocks immortal. **Insert no `release` calls yet** —
  behaviour is identical to today (leak-on-exit), so risk is ~zero. Validates the
  header layout, literal interning, and arena composition in isolation.
- **3b — Release owned locals in pure functions.** The safest slice: pure-kind
  bodies borrow their params, so only locals and the return need handling. Insert
  scope-exit `release` for owned locals, `move` the return out. Pure functions are
  the majority of the compiler, so this exercises the machinery hard while the
  rules are simplest. Gate: self-host runs clean under ASan.
- **3c — Full ownership transfer at call boundaries.** Extend to
  `producer`/`creator`/`consumer`/`action`: retain on store, consume on
  consumer params, release-old on rebind, retain on field/array writes.
- **3d — Optimise.** Activate `move`/`own`/`dup` to elide counts; add `weak`;
  optional escape-analysis tightening where a kind under-specifies.

## Validation

- **AddressSanitizer build of the compiler** running the full example suite +
  self-host: catches use-after-free and double-free immediately.
- **Self-host fixpoint** must stay byte-identical (codegen stays deterministic)
  *and* the gen2/gen3 compilers must run correctly with ARC'd memory.
- **Leak measurement:** a long `web.serve` loop under massif/heaptrack should show
  flat (not growing) heap — the actual success metric for the server case.
- The existing `xi test` suite under ASan.

## Risks and fallbacks

- **Use-after-free** is the real danger (worse than the current leak). Mitigations:
  the per-kind rules are conservative (bias toward retaining/leaking over freeing
  early); 3a→3d is incremental; ASan + self-host catch errors fast.
- **Opt-in flag during development.** Gate ARC codegen behind `XC_ARC=1` (or a
  `--gc=arc` flag) so `main` keeps self-hosting with ARC **off** while it matures,
  flipping the default only once the ASan self-host is clean across all examples.
- **Cycles** leak rather than crash — acceptable for v1; `weak` and the acyclic
  value model keep them rare.

## Sequencing note

The place leaking *actually* hurts today is `web.serve` (per-request strings/DTOs).
The remaining **Phase-1 per-request arena** — an implicit region freed after each
request — is a much smaller, lower-risk change that fixes the server case
directly and can land *before* full ARC. Recommended order: finish the
per-request arena (quick win), then ARC 3a→3d (general solution). ARC then
subsumes the arena for everything that escapes a single request.

## Open questions

- Header size/placement for arrays (the fat pointer already has `cap`; the header
  sits before `data`, same as strings).
- Literal interning table: per-translation-unit static cache keyed by the C
  literal pointer, or a global hash? (Leaning: per-TU pointer-keyed — literals are
  unique C objects.)
- Do boxed instances need per-field release (recursively releasing owned
  String/array fields), and where is that "destructor" emitted — one
  `xc_release_<Class>` per class, called from `xc_release` via a type tag?
- Does `dup` on an array deep-copy elements or just retain the backing store
  (shared-immutable means retain is enough until a write — but arrays can grow)?
- Is escape analysis (Phase E) ever needed on top, or do the kind rules + `weak`
  cover it? (Leaning: kinds cover it; revisit only if a real case escapes them.)
