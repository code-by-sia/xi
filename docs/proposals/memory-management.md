# Proposal: Memory management — does Ξ need a GC?

> **Status: draft / exploration.** This document weighs the options and
> recommends a direction. **Nothing here is implemented yet.**

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

## Recommendation — a phased, hybrid path

No single mechanism wins outright, so combine the ones that respect the
philosophy and skip the one that doesn't (tracing GC):

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

2. **Phase 2 — automatic reference counting for escaping heap values.** Make ARC
   the general answer for values that outlive their scope (strings, arrays, boxed
   instances). Give `own`/`move`/`dup` real meaning as ownership-transfer hints
   that elide counts, and add a `weak` reference for the rare back-edge. This
   delivers GC-like ease with no runtime dependency and predictable timing — the
   best fit for all three commitments.

3. **Phase 3 (exploration) — opt-in borrows for hot paths.** Turn the existing
   `&T` / `&mut T` into a *small, local, optional* borrow rule (no lifetime
   syntax) so performance-critical code can pass by reference and skip both the
   copy and the refcount. Strictly opt-in; the language stays learnable without it.

4. **Rejected: a default tracing GC**, and **any external GC/runtime library** —
   both break "fast + least-dependency," and ARC recovers most of the ease.

### Why this fits the philosophy

- **Fast:** bump-arena + ARC + optional borrows are all deterministic and
  close-to-C; no stop-the-world pauses.
- **Least dependency:** everything is generated C over libc — no GC runtime, no
  third-party library.
- **Easy:** the default path (arenas + ARC) needs zero new concepts from the
  user; borrowing exists only for those who opt in.

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

- Refcount **granularity**: only heap values (strings/arrays/boxes), or all
  compounds? (Leaning: only heap-backed values; small structs stay pure copies.)
- **Cycle policy**: rely on the immutable/acyclic model + `weak`, or ship a small
  opt-in cycle detector?
- Where exactly does **Phase-1 arena** scoping attach — the `scope` block, a new
  `arena { }`, or purely implicit in `web.serve`/request handlers?
- Is **escape analysis** (Phase E) worth it on top of ARC, or does ARC already
  cover enough?
- Do we want a compile-time **leak/ownership lint** (warn when an `own` value is
  dropped without being consumed) as a gentle on-ramp to Phase 3?
