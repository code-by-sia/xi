# Proposal: Closures & generics (the remaining collections work)

> **Status: draft / design.** The collections layer is **complete** — `List`/`Set`/
> `Map`, the eager functional API, lazy `Sequence`s, `Pair<A,B>`,
> `zip`/`partition`/`unzip`, and now **`generateSequence`** (infinite sources) all
> ship (see [Collections](../collections.md); `generateSequence` fuses the inlined
> generator into the sequence loop, so it needed no first-class closures).
>
> What remains is the genuinely large language work this proposal exists for —
> **first-class closures** (lambdas as *values*: passed, stored, returned) and
> **generics** (monomorphized user types/functions). These are a deliberate
> multi-step effort, not a collections gap; everything the collections layer needs
> is now built.

## Why these two

The functional operators today take *inlined* lambda blocks (`xs.map { it * 2 }`)
that the compiler fuses directly into a loop — they are not values. Two features
generalize that:

### 1. Generics (monomorphization)

Ξ already monomorphizes the built-in `T[]` array (`xc_arr_<T>_t` + helpers per
element type). **Generics generalize that machinery** to user types and functions:
for each concrete instantiation used, emit one specialized version — **no boxing,
no runtime cost**. Type arguments are inferred at call/construction sites; type
parameters start unbounded and gain interface bounds (`K: Hashable`,
`T: Comparable`) where maps and sorting need them. This also cleans up typed
events/channels (which currently round-trip through JSON).

### 2. Closures / lambdas (first-class function values)

The functional operators carry behaviour, so we need function *values*. Two forms,
reusing Ξ's `=>`:

```x
xs.map(o => o.total)            // explicit parameter
xs.filter { it > 0 }            // trailing lambda + implicit `it` (single param)
ys.fold(0) { acc, x => acc + x }
```

A closure lowers to an env struct (captured values) + a function pointer — the
same shape the `parallel { }` block already lifts to; **no new runtime**. Capture
is **by value** (matches Ξ's value semantics, stays share-nothing-friendly). A
closure passed to a *fused* sequence never escapes → **zero allocation**; an
escaping one is reclaimed by the arena/`scope` model.

## What this unblocks

- **`generateSequence(seed) { next(it) }`** — infinite/lazy sources, the last open
  collections item: `generateSequence(1) { it * 2 }.take(10).toList()`.
- **First-class operators** — passing/storing/returning lambdas, not just inlining
  them at call sites.
- **Generic user containers** (`ArrayDeque<T>`, `PriorityQueue<T>`, ordered maps)
  on the same zero-cost basis as `T[]`.
- **Typed events/channels** without the JSON round-trip.

## Build plan & status

First-class closures are a coherent, multi-step codegen subsystem. The steps,
with the design fixed (mirroring how `Pair` and `parallel {}` already work):

0. **Runtime + type encoding — DONE.** `xc_fn_t { void* fn; void* env; }` (a code
   pointer + captured-env pointer) and the `Fn(<params>)(<ret>)` xtype encoding
   (balanced-paren, like `Pair`), with `xnameToCtype(Fn…) = xc_fn_t`. Additive;
   self-host byte-identical.
1. **Lambda expression** `(p: T, …) => expr` in `genPrimary` → emit an `xc_fn_t`
   value `{ .fn = __lam_<id>, .env = <heap env> }`, xtype `Fn(…)(…)`.
2. **Lambda hoist pass** (mirror `hoistParallel`): for each lambda, emit a
   top-level `static R __lam_<id>(void* env, params…)` plus an env struct; wire
   into `genAll` like `hoistParallel`. Keyed by token position so the call site
   names the same helper.
3. **Capture analysis:** scan the lambda body for identifiers that are outer
   locals/params (in scope, not lambda params) and copy them **by value** into the
   env struct (`NULL` env when capture-free).
4. **Call-through:** `f(args)` where `f` is `Fn(P…)(R)` → cast `f.fn` to
   `R(*)(void*, P…)` and invoke `f.fn(f.env, args…)`; result xtype = `R`.
5. **Function types in signatures** — `parseTypeExpr` parses `(T, …) -> U`.
6. **The blocker for higher-order functions:** a function-typed *parameter*
   currently derives its xtype from its ctype (`addParamSym` → `ctypeToXName`),
   which collapses every `Fn(…)` to the uniform `xc_fn_t` and **loses the
   signature** needed to call it. So params must carry the full xtype alongside
   the ctype (a small but cross-cutting change to the param channel). Until then,
   only *local* closures (bound + called in the same function) work; passing
   lambdas across function boundaries — the point of higher-order functions —
   needs this step. **This is why the feature is multi-session, not one-pass.**

**Generics (monomorphization)** is a separate large feature (generalize the
`T[]` per-element specialization to user types/functions, with inferred type
args and interface bounds). It is *not* required for closures and is tracked here
as the second half of the proposal.

## Why this fits the philosophy

- **Fast:** monomorphization + inlined/fused closures = real zero-cost
  abstractions, the way `T[]` already is.
- **Least dependency:** all generated Ξ/C over libc — no runtime.
- **Easy:** a fluent, familiar API; lambdas reuse `=>`; no lifetimes to learn.

## Open questions

- **`it` and trailing lambdas:** keep the current inlined `{ it }` block sugar as
  the surface for closures too, or distinguish value-lambdas syntactically?
- **Generic bounds** from day one (needed for `Map` keys / `PriorityQueue`) vs
  later.
- **Capture scope:** value-capture only (current leaning), or allow capturing a
  mutable cell?
- **Destructuring** (`let (k, v) = pair`, `for (k, v) in m`) now that `Pair`
  exists.
