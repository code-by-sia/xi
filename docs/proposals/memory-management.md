# Proposal: Memory management — does Ξ need a GC?

> **Status: accepted direction (phased), implementation pending.** This document
> weighs the options and commits to a path: a phased hybrid (arenas → ARC →
> opt-in borrows) in which **the function effect kinds drive the analysis**.
> Phase 1's per-thread arenas are shipped; the rest is designed, not yet built.

## The question

How should Ξ manage heap memory? The answer has to honour the language's three
standing commitments, which pull in slightly different directions:

1. **Fast** — predictable, close-to-C performance; no surprise pauses.
2. **Least dependency** — Ξ → C99 → a native binary with nothing but the system
   `cc` and libc. A memory strategy that drags in a third-party runtime (a GC
   library, say) breaks this.
3. **Easy to learn** — no concept that costs a newcomer a week. Lifetime
   *borrowing* (Rust-style) is the canonical example of what we'd rather not
   *force* on people — though it's worth exploring as an opt-in.

These can't all be maxed at once: tracing GC trades predictability and a runtime
for ease; borrow checking trades ease for speed and zero runtime. The job of this
proposal is to pick the trade that best fits the philosophy.

## Where we are today

Ξ currently uses **allocate-and-leak**: every heap value — a `String` buffer
(`xc_str_copy`), an array's backing store, a DI-boxed class instance
(`xc_new_*`), an event/channel payload — is `malloc`'d and **never freed**. The
process reclaims everything on exit. The runtime's `free` calls are only for
short-lived C scratch (e.g. the `char*` from `xc_string_to_cstr`), not for
language-level values.

This is deliberate and it's *fine* for the common case so far:

- The **compiler itself** runs once and exits — leaking is simply the fastest
  arena strategy (no bookkeeping, no frees).
- Short-lived CLIs behave the same way.

It is **not** fine for long-running programs. `web.serve` leaks every request's
strings/DTOs; a server is the first place this bites. Threading and events have
the same property for anything that outlives a drain.

Two pieces of relevant grammar already exist but are **parsed and ignored**:

- `own` / `dup` / `move` storage qualifiers (lexed as keywords today).
- `&T` / `&mut T` reference types in `parseTypeExpr` (they lower to C pointers,
  with no checking).

So there's room to give these meaning later without new syntax.

Two properties of the language make this much easier than for a typical
imperative language:

- **Value semantics.** Strings and compounds are immutable values; you replace,
  never mutate in place. Immutable, acyclic data is the friendliest possible
  input to *any* reclamation scheme (no cycles, no shared-mutable aliasing).
- **Share-nothing threads.** Threads exchange only copied channel payloads, so
  memory ownership never crosses a thread boundary — no concurrent collector or
  atomic refcounts required.

## The lever: effect kinds already encode ownership

Every Ξ function declares an **effect kind** — the verb you write instead of
`fn`. That keyword is not just documentation; it is a contract about what the
function may do, and therefore about how values flow through it. A normal
language has to *recover* this information with whole-program escape analysis or
make the programmer *spell it out* with lifetime annotations. Ξ has it stated up
front, on every function, in a word the author already had to choose.

Read each kind as an ownership/escape rule:

| Kind | Contract (what it may do) | Memory consequence |
|------|---------------------------|--------------------|
| `mapper` | pure `T -> U`; no I/O, no mutation, no storing | args **borrowed** (no copy, no retain); only the fresh return escapes → caller owns it |
| `projector` | pure structural extraction; returns a part of its input | return **borrows from** the argument — no allocation at all; arg must outlive the result |
| `predicate` | pure `T -> Bool` | args **borrowed**; result is scalar → **nothing escapes** |
| `reducer` | `(Acc, T) -> Acc` fold | `Acc` is **moved** in and out (ownership threads through, no retain); `T` borrowed — enables in-place accumulator reuse |
| `creator` | constructs instances | the **ownership origin**: returns a freshly **owned** heap value |
| `producer` | `() -> T`, often I/O | effectful; returns **owned** (typically fresh) |
| `consumer` | side-effecting, no return | terminal **sink**: may take ownership of its inputs (free them, or store them) |
| `action` | impure; may mutate `self`/state | may **retain** an argument into long-lived state |

Two consequences follow, and they are the heart of this proposal:

1. **Escape analysis becomes a lookup, not a pass.** A `mapper`/`predicate`/
   `projector` *cannot* (by enforced contract) stash an argument anywhere
   observable, so its arguments provably do not escape. That is precisely the
   fact a borrow checker extracts from lifetimes and an optimiser extracts from
   global escape analysis — here it is given by one keyword. The compiler can
   pass those arguments by **borrow** and skip both the copy and the refcount,
   *automatically*, with no `&T` syntax and nothing for the user to learn.

2. **Retains happen only at the kinds that take ownership.** A reference count is
   bumped only where a value genuinely changes owner — a `creator`/`producer`
   return handed into storage, an argument captured by an `action`, a value
   moved into a `consumer`. Everywhere else (the overwhelmingly common pure
   path) the value is borrowed and the count is never touched. ARC's main cost —
   count traffic — is concentrated exactly where ownership actually moves.

This is the "restrict developers to do certain things in certain functions"
point made precise: the compiler **enforces** each kind's contract (a `mapper`
that performs I/O, mutates, or calls an effectful function is a *compile error*),
and **in exchange** it is allowed to apply aggressive borrow/no-retain codegen
that would be unsound without the guarantee. Enforcement is not a tax — it is
what *buys* the optimisation. The discipline the author accepts when they type
`mapper` is the same discipline the allocator relies on.

## The design space

### A. Status quo: allocate-and-leak (+ explicit arenas)

Keep leaking, but add a **scoped arena**: a region you allocate into and free in
one shot at the end of a block (a natural fit for the existing `scope` keyword,
or an implicit per-request region in `web.serve`).

- **Fast:** the fastest possible — bump-pointer allocation, bulk free.
- **Dependency:** zero.
- **Easy:** trivial mental model ("things live until the region ends").
- **Cost:** values can't escape their region without a copy; needs either a
  copy-out convention or light escape analysis. Unbounded growth *within* a
  long-lived region (one request that builds a huge structure) is still on the
  programmer.

### B. Tracing garbage collection (mark-sweep / generational)

A runtime that periodically traces live objects from roots and frees the rest.

- **Easy:** the most forgiving for users — allocate freely, never think about it.
- **Fast:** *amortised* good, but with pauses and unpredictable latency — poor
  for a server tail, and at odds with "predictable, close-to-C."
- **Dependency:** the killer. Either (a) link a library like Boehm — a real
  external dependency that breaks commitment #2 and isn't precise; or (b) **write
  our own** precise tracing GC — which needs stack-root scanning, a shadow stack
  or precise stack maps, per-type trace metadata, and a safepoint protocol. That
  is a large, subtle, ongoing maintenance burden inside a project whose selling
  point is a small self-hosting compiler.
- **Verdict:** **rejected** as the default. It's the worst fit for "fast +
  least-dependency," and the ease it buys is also largely bought by option C
  without the runtime.

### C. Automatic reference counting (ARC)

The compiler inserts retain/release around heap values; an object is freed when
its count hits zero. No user-visible lifetimes.

- **Easy:** essentially invisible — same "just allocate" feel as a GC.
- **Dependency:** zero (it's just generated `inc`/`dec`/`free` calls + a count
  word per heap object).
- **Fast:** deterministic, no pauses; cost is the count traffic. Crucially, Ξ's
  value-semantic, immutable data means most refcount churn is on copies that the
  compiler can elide, and `move`/`own` (already in the grammar!) can hand off
  ownership without a retain.
- **Cost / risk:** reference *cycles* leak. But cycles require shared mutable
  references, which Ξ's immutable value model largely precludes; where they're
  possible (e.g. an interface holding a back-reference), a `weak` qualifier or a
  documented "no cycles in owned data" rule covers it. Threading is safe because
  ownership never crosses the share-nothing boundary, so counts need **no atomics**.
- **Verdict:** **strong candidate** for the general heap.

### D. Ownership + borrowing (Rust-style)

Single owner, compile-time borrow checker, zero runtime cost.

- **Fast / dependency:** unbeatable — no runtime, no counts, no pauses.
- **Easy:** this is the one that violates commitment #3. A *full* borrow checker
  (lifetimes, borrow scopes, variance) is exactly the "costs a week" concept.
- **But worth exploring as opt-in:** Ξ already has `&T` / `&mut T` and
  `own`/`move`. A *lightweight, non-mandatory* borrow — function parameters that
  take `&T` to avoid a copy, checked only by simple, local rules (no lifetime
  annotations, no escaping borrows) — could give hot paths zero-copy speed
  **without** making anyone learn lifetimes. The full checker stays off by default.
- **Verdict:** **explore as an optional optimisation layer**, never the baseline.

### E. Region/arena with escape analysis

Like A, but the compiler infers which allocations can live in a scope's region
and which must outlive it (and so go on the long-lived heap).

- A nice automatic middle ground, but the escape analysis is real compiler work
  and the model gets fuzzy at the edges (partial escapes). Reasonable as a
  *later* optimisation over A+C, not as the first step.

## Recommendation — effect-kind-driven, phased

No single mechanism wins outright, so combine the ones that respect the
philosophy (arenas, ARC, borrows), skip the one that doesn't (tracing GC), and —
the decision this revision makes — **drive all of them from the effect kinds**
rather than from a separate analysis pass or new lifetime syntax. The phases
below are ordered by effort, but they share one engine: the per-kind ownership
contract above.

1. **Phase 1 — bounded lifetimes for long-running programs (small, do first).**
   Keep allocate-and-leak as the default (it's optimal for CLIs and the
   compiler), but add an **arena tied to a scope** plus an **implicit per-request
   arena in `web.serve`**, so servers stop leaking without any user ceremony.
   Zero dependency, trivial to teach, immediately fixes the only place the status
   quo actually hurts.
   - **Shipped: per-thread arenas.** Each spawned thread allocates its values
     (strings, JSON nodes) from its own arena, freed when the thread finishes —
     so a thread reclaims everything it used on exit. The main thread is
     unaffected; the share-nothing channel copy makes this safe. (Still freed at
     thread *exit*, not per scope/iteration — that's the remaining Phase-1 work.)

2. **Phase 2 — effect-kind borrow inference (the new core; do before ARC).**
   Before adding any counting, exploit what the kinds already prove. Pure kinds
   (`mapper`, `predicate`, `projector`) take their arguments **by borrow**: no
   copy, no retain, because the contract guarantees the argument cannot escape.
   `reducer` threads its accumulator by **move**. This is the escape analysis and
   the "opt-in borrow" of the original plan — but *derived, automatic, and free*,
   because the keyword supplies the fact a borrow checker would otherwise demand
   as a lifetime annotation. Prerequisite and enabler: **enforce purity** — a
   `mapper`/`predicate`/`projector` that performs I/O, mutates, or calls an
   effectful function becomes a compile error. That check is independently good
   (it makes the kinds mean what they say) and it is what makes the borrow codegen
   sound.

3. **Phase 3 — automatic reference counting for the values that genuinely
   escape.** With borrows handling the pure majority, ARC carries only the
   minority that crosses an ownership boundary: a `creator`/`producer` return
   stored past its scope, an argument an `action` retains into state, a value a
   `consumer` takes. The compiler inserts retain/release only at those kind
   boundaries, so count traffic is small by construction. `own`/`move`/`dup`
   (already in the grammar) become explicit ownership-transfer hints that elide
   counts; `weak` covers the rare back-edge. GC-like ease, no runtime dependency,
   predictable timing — and far less counting than a kind-blind ARC.

4. **Phase 4 (exploration) — explicit borrows where the kind isn't enough.** The
   `&T` / `&mut T` types remain as an *opt-in* escape hatch for the cases the
   effect kind can't classify on its own (e.g. passing a large owned value into
   an `action` you want borrowed, not retained). Small, local rules; no lifetime
   syntax. Most code never needs it because Phase 2 already borrows wherever a
   pure kind proves it safe.

5. **Rejected: a default tracing GC**, and **any external GC/runtime library** —
   both break "fast + least-dependency," and the effect-kind borrows + ARC
   recover the ease.

The reordering matters: in the original plan, borrows/escape analysis were the
*last*, hardest, optional phase. Recognising that the effect kinds already carry
the ownership information **promotes borrow inference to the core mechanism and
demotes ARC to a fallback**, which is both less runtime cost and less compiler
machinery than an ARC-first design.

### Why this fits the philosophy

- **Fast:** bump-arena + effect-kind borrows + ARC-on-escape are all
  deterministic and close-to-C; no stop-the-world pauses. Most values are
  borrowed, so the common path touches no counts at all.
- **Least dependency:** everything is generated C over libc — no GC runtime, no
  third-party library.
- **Easy:** the user learns *nothing new*. They already pick `mapper` vs
  `creator` vs `consumer`; the allocator simply reads that choice. No lifetime
  syntax, no annotations — the borrow discipline rides on the effect verb the
  author was already writing.
- **Coherent:** the same effect kinds that drive dispatch, purity, and
  documentation now also drive memory. One concept, paying for itself several
  times over.

## Interactions to keep in mind

- **Value semantics & immutability** are what make ARC cheap and cycle-free here;
  preserve them.
- **Share-nothing threads** mean counts can stay non-atomic — don't add shared
  mutable heap ownership across threads.
- **DI boxing** (`xc_new_*`): singletons are process-lifetime (never freed by
  design); only `transient`-scoped instances need reclamation.
- **`scope`, `own`, `move`, `dup`, `&`, `&mut`** already exist in the grammar —
  the plan gives them semantics rather than inventing new syntax.

## Open questions

- **Purity enforcement scope (Phase 2 prerequisite):** exactly which operations
  disqualify a `mapper`/`predicate`/`projector` — clearly I/O, mutation, and
  calling an `action`/`consumer`/`producer`; but what about calling another
  `mapper` (fine) or reading process-lifetime DI singletons (probably fine, since
  they never free)? The call graph must classify "pure-callable" cleanly.
- **`projector` return-borrow lifetime:** a projector returns a view into its
  argument, so the result must not outlive the input. With Phase-2 borrows this
  is usually local and checkable, but storing a projector result needs a copy or
  a retain on the underlying value — decide the rule.
- **`reducer` move semantics:** confirm the accumulator can always be moved (not
  retained) through a fold, including when the reducer is used by a higher-order
  collection op that itself holds the accumulator.
- **Refcount granularity** (Phase 3): only heap values (strings/arrays/boxes), or
  all compounds? (Leaning: only heap-backed values; small structs stay pure
  copies.)
- **Cycle policy:** rely on the immutable/acyclic model + `weak`, or ship a small
  opt-in cycle detector?
- Where exactly does the **Phase-1 arena** scoping attach — the `scope` block, a
  new `arena { }`, or purely implicit in `web.serve`/request handlers?
- Do we want a compile-time **leak/ownership lint** (warn when an `own` value is
  dropped without being consumed) as a gentle on-ramp to explicit borrows?
- **Resolved by this revision:** "is escape analysis worth it on top of ARC?" —
  yes, and it comes for free from the effect kinds, which is why borrow inference
  is now Phase 2 (ahead of ARC) rather than an optional late phase.
