# Proposal: Collections, streams & generic data structures

> **Status: draft / design.** Decides the *shape* of Ξ's collection and lazy-
> stream APIs and the two language features they rest on. **Nothing here is
> implemented yet.**

## Goal

Give Ξ a proper data-structure layer — growable lists, maps, sets, and **lazy
streams** — that honours the three commitments:

- **Fast** — zero-cost abstractions: no boxing, no per-stage allocation, close to
  hand-written C.
- **Least dependency** — pure Ξ → C99 over libc; no runtime container library.
- **Easy** — a familiar fluent API (`xs.map(...).filter(...)`), `for x in`, and
  lambdas that read like the inline function bodies we already have.

## The two prerequisites (decided)

Collections and streams rest on two language features. Both are **decided** as
the path forward:

### 1. Generics (monomorphization) — *first*

A reusable `List<T>` / `Map<K,V>` / `Stream<T>` needs a type parameter. Ξ already
monomorphizes the built-in `T[]` array (the compiler emits `xc_arr_<T>_t` and its
helpers per element type). **Generics generalize exactly this machinery** to user
types and functions: for each concrete instantiation actually used, emit one
specialized version.

```x
type List<T> = { ... }                 // generic type
mapper map<T, U>(xs: List<T>, f: ...) -> List<U> { ... }   // generic function

let xs: List<Integer> = List()         // monomorphized to a concrete struct
```

- **No boxing, no runtime cost** — each instantiation is a distinct concrete type,
  like `T[]` today.
- **Inference**: infer type arguments at call/construction sites where possible
  (`List()` in a `List<Integer>` context; `xs.map(double)` from `xs`'s element).
- **Bounds**: start with *unbounded* type parameters; add interface bounds
  (`T: Hashable`, `T: Ord`) when maps/sorting need them — expressed with the
  interfaces we already have.
- This is the highest-leverage missing piece: it also cleans up typed events and
  typed channels, which currently round-trip through JSON.

### 2. Closures / lambdas — *for streams*

Stream operations carry behaviour (`map`/`filter`/`reduce`), so we need function
values. The syntax reuses the inline-body arrow already in the language:

```x
xs.map(o => o.total)                    // expression lambda
xs.filter(o => { return o.active })     // block lambda
ys.reduce(0, (a, b) => a + b)
```

- **Representation:** a closure is an env struct (captured values) + a function
  pointer — the same shape the `parallel { }` block already lifts to. Lowered to a
  generated function plus a small env; **no new runtime**.
- **Capture by value**, matching Ξ's value semantics and keeping it share-nothing-
  friendly (a closure can cross into a thread the way a captured channel does).
- **Memory:** a closure passed to a *fused* stream (below) never escapes and needs
  **zero allocation**; an escaping closure follows the
  [memory-management plan](memory-management.md) (arena/ARC).

## Eager collections — `std/collections`

Mutable, heap-backed, generic. `T[]` stays the primitive; `List<T>` is the
growable layer over it.

```x
let xs = List<Integer>()          // empty; or [1, 2, 3].toList()
xs.push(4)
xs.len()                          // 4
xs.get(0)                         // Integer? (bounds-checked)
xs.set(0, 9)
xs.contains(9) / xs.indexOf(9)
xs.removeAt(2) / xs.insert(1, 7) / xs.clear()
xs.toArray()                      // back to a T[]

let m = Map<String, User>()
m.set("ada", u)
m.get("ada")                      // User?
m.has("ada") / m.remove("ada") / m.len()
m.keys() / m.values() / m.entries()

let s = Set<String>()
s.add("x") / s.has("x") / s.remove("x")
s.union(t) / s.intersect(t) / s.difference(t)
```

- **`Map`/`Set` keys** need equality + hashing: built in for primitives and
  `String`; for user types, an interface bound (`K: Hashable`).
- **Semantics:** lists/maps/sets are **reference-like mutable** values (a handle
  to a heap structure) — the conventional, least-surprising choice — with
  reclamation handled by the memory-management plan. (Open question below.)

## Lazy streams — `std/stream`

A `Stream<T>` is a lazy pipeline. The headline property is **loop fusion**: a
chain compiles to a *single* loop with no intermediate collections and the
closures inlined — the zero-cost form of laziness, no iterator objects, no
allocation.

```x
let total = stream(orders)
    .filter(o => o.active)
    .map(o => o.total)
    .reduce(0.0, (a, b) => a + b)        // one fused loop, no temp lists
```

**Sources:** `stream(xs)` (over a List/array), `range(0, n)`, `repeat(x)`,
`iterate(seed, f)` (infinite), `once(x)`, `empty()`.

**Lazy ops (return `Stream<U>`):** `map`, `filter`, `take(n)`, `drop(n)`,
`takeWhile`, `dropWhile`, `flatMap`, `zip`, `enumerate`, `distinct`, `scan`.

**Terminals (force the pipeline):** `reduce` / `fold`, `collect()` → `List<T>`,
`toArray()`, `forEach(f)`, `count()`, `sum()`, `any(p)` / `all(p)`, `find(p)` →
`T?`, `first()` → `T?`, `min` / `max`.

Infinite sources are fine when bounded downstream:
`iterate(1, n => n * 2).take(10).collect()`.

## The iterable protocol

To let user types flow into streams and `for x in`, a tiny generic interface:

```x
interface Iterator<T> { mapper next() -> T? }       // None ends the sequence
interface Iterable<T> { mapper iterator() -> Iterator<T> }
```

- `for x in xs` already works on arrays; generalize it to anything `Iterable<T>`.
- `List`/`Map`/`Set`/ranges implement `Iterable`; `stream(it)` accepts any
  `Iterable<T>`. A `Sequence<T>` is just an `Iterable<T>` whose source is lazy.

## Other data structures (follow-ons)

Built on the generic core, added as needed rather than up front:

- `Deque<T>` / `Queue<T>` / `Stack<T>` — thin layers over `List<T>`.
- `PriorityQueue<T>` (binary heap), needs `T: Ord`.
- Ordered/sorted `Map`/`Set` (balanced tree) when iteration order matters.
- `LinkedList<T>` only if a real use-case appears (rarely worth it).

## Phasing

1. **Generics** (monomorphization) — the foundation; also benefits events/channels.
2. **`std/collections`** — `List`, `Map`, `Set` (eager), with `for x in` support.
3. **Closures / lambdas** (`x => expr`), capture-by-value, lowered like `parallel`.
4. **`std/stream`** — lazy, loop-fused `Stream<T>` + the `Iterable`/`Iterator`
   protocol.
5. Extra structures (`Deque`, `PriorityQueue`, sorted maps) on demand.

## Why this fits the philosophy

- **Fast:** monomorphization (no boxing) + inlined closures + loop fusion =
  genuine zero-cost abstractions, the same way `T[]` is today.
- **Least dependency:** everything is generated Ξ/C over libc — no container or
  iterator runtime.
- **Easy:** fluent `.map().filter()`, `for x in`, and `=>` lambdas that mirror the
  inline function syntax already in the language; no lifetimes to learn.

## Open questions

- **Collection semantics:** reference-mutable (proposed) vs value + copy-on-write?
  The latter is more consistent with Ξ's immutable values but costs copies.
- **Map key bounds:** built-in hashing for primitives/strings + a `Hashable`
  interface bound for user keys — exact interface shape (`hash()` + `eq()`?).
- **Generic bounds:** unbounded to start, or interface bounds from day one
  (needed for `Map` keys and `PriorityQueue`)?
- **Type-argument inference** depth — constructors and obvious call sites only, or
  full bidirectional inference?
- **Closure capture** — by value only (proposed), or allow `&mut` captures later?
- **Naming** — `Stream` vs `Sequence` vs `Iter`; `collect` vs `toList`.
- **`Result`/`Option` ergonomics** in pipelines (`filterMap`, `tryCollect`).
