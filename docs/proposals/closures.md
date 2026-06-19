# Proposal: Closures & generics (the remaining collections work)

> **Status: draft / design.** The collections layer is implemented — `List`/`Set`/
> `Map`, the eager functional API, lazy `Sequence`s, `Pair<A,B>`, and
> `zip`/`partition`/`unzip` all ship (see [Collections](../collections.md)). The
> one collections item left, `generateSequence` (infinite sources), needs
> **first-class closures**, which is the real subject of this proposal — along with
> the **generics** that would let user types/functions be parameterized the way the
> built-in containers already are.

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

## Phasing

1. **Generics (monomorphization)** — the foundation; also benefits events/channels.
2. **Closures / lambdas** (`=>` and trailing `{ it }`), capture-by-value.
3. **`generateSequence`** and first-class functional operators on top.
4. Extra generic structures (`ArrayDeque`, `PriorityQueue`, ordered maps) on demand.

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
