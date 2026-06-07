# Proposal: Collections, sequences & generic data structures

> **Status: draft / design.** Decides the *shape* of Ξ's collection and lazy-
> sequence APIs and the two language features they rest on. The design takes
> inspiration from several modern collection libraries but is tailored to Ξ —
> value semantics, no `null` (optionals via `T?` / `none`), and a C99 backend.
> **Nothing here is implemented yet.**

## Goal

Give Ξ a complete data-structure layer — read-only and mutable lists, maps, and
sets; a rich functional API; and lazy **sequences** — that honours the three
commitments:

- **Fast** — zero-cost: monomorphized (no boxing), closures inlined, lazy chains
  fused into a single loop; close to hand-written C.
- **Least dependency** — pure Ξ → C99 over libc; no container/iterator runtime.
- **Easy** — a fluent, familiar surface: `listOf(...)`, `xs.map { ... }`,
  `asSequence()`, `for x in xs`.

## The two prerequisites (decided)

### 1. Generics (monomorphization) — *first*

Ξ already monomorphizes the built-in `T[]` array (`xc_arr_<T>_t` + helpers per
element type). **Generics generalize that machinery** to user types and
functions: for each concrete instantiation used, emit one specialized version —
**no boxing, no runtime cost**. Type arguments are inferred at call/construction
sites; type parameters start unbounded and gain interface bounds (`K: Hashable`,
`T: Comparable`) where maps and sorting need them. This also cleans up typed
events/channels (which currently round-trip through JSON).

### 2. Closures / lambdas — *for the functional API*

The functional operators carry behaviour, so we need function values. Two forms,
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
escaping one follows the [memory-management plan](memory-management.md).

## Read-only vs mutable

Collections come in a read-only interface and a mutable sub-interface. Most code
takes the read-only type; only code that needs to grow it asks for the mutable
one — a cheap, learnable way to express intent without a borrow checker.

```x
interface List<T>          { ... }          // size, get, contains, iterator, + functional ops
interface MutableList<T>   extends List<T>  // add, set, removeAt, clear, ...
interface Set<T>           { ... }          interface MutableSet<T> extends Set<T>
interface Map<K, V>        { ... }          interface MutableMap<K, V> extends Map<K, V>
```

**Builders:**

```x
let a = listOf(1, 2, 3)              // List<Integer> (read-only)
let b = mutableListOf<Integer>()     // MutableList<Integer>
let m = mapOf("ada" to 1, "bo" to 2) // Map<String, Integer>
let s = setOf("x", "y")
let e = emptyList<String>()
let built = buildList { it.add(1); it.add(2) }   // build then freeze
```

`a to b` is infix sugar for `Pair(a, b)`; `Pair<A, B>` has `.first` / `.second`.

## The functional API (eager, on `List`/`Iterable`)

A broad functional operator set, returning new collections (eager). Names that
elsewhere reference `null` are tailored to Ξ optionals (e.g. `mapNotNone`,
`filterNotNone`, `firstOrNone` returning `T?`). A representative slice:

```x
xs.map { it * 2 } / mapIndexed / mapNotNone
xs.filter { it > 0 } / filterNot / filterNotNone
xs.forEach { ... } / forEachIndexed
xs.fold(0) { a, x => a + x } / reduce / runningFold(=scan)
xs.flatMap { it.tags } / flatten
xs.groupBy { it.kind } / associateBy / associateWith / partition { it.active }
xs.chunked(3) / windowed(2) / zip(ys) / unzip
xs.distinct / distinctBy { it.id } / sorted / sortedBy { it.age } / reversed
xs.take(3) / takeLast / takeWhile { ... } / drop / dropWhile / slice(1..3)
xs.first / firstOrNone / last / lastOrNone / find { ... } / single
xs.any { ... } / all / none / count { ... }
xs.sumOf { it.total } / maxByOrNone { it.age } / minOf / average
xs.joinToString(", ") { it.name } / contains / indexOf / elementAtOrNone
xs + ys / xs - zs                  // plus / minus
```

**Maps:** `m.get(k)` → `V?`, `getValue`, `getOrElse(k) { ... }`,
`getOrPut(k) { ... }` (mutable), `keys` / `values` / `entries`, `filterKeys` /
`filterValues`, `mapValues { it.value + 1 }` / `mapKeys`, `forEach { k, v => ... }`,
`toList()` → `List<Pair<K, V>>`.

## Lazy `Sequence<T>`

`asSequence()` switches a collection to lazy evaluation; the same operators apply
but nothing runs until a terminal. The headline property is **loop fusion**: the
whole chain compiles to a *single* loop with the closures inlined — no
intermediate collections, no iterator objects, no allocation.

```x
let total = orders.asSequence()
    .filter { it.active }
    .map    { it.total }
    .fold(0.0) { a, b => a + b }     // one fused loop
```

**Sources:** `asSequence()`, `sequenceOf(...)`, `generateSequence(seed) { next(it) }`
(infinite), `(1..n).asSequence()`. **Lazy intermediates:** `map`/`filter`/`take`/
`drop`/`takeWhile`/`flatMap`/`distinct`/`zip`/`mapIndexed`/`scan`. **Terminals:**
`toList` / `toMutableList` / `toSet` / `forEach` / `fold` / `reduce` / `count` /
`sum` / `any` / `all` / `find` / `first(OrNull)` / `max(By)OrNull`. Infinite
sources are fine when bounded: `generateSequence(1) { it * 2 }.take(10).toList()`.

## Iteration protocol & ranges

```x
interface Iterator<T> { mapper hasNext() -> Bool   mapper next() -> T }
interface Iterable<T> { mapper iterator() -> Iterator<T> }
```

- `for x in xs` (already works on arrays) generalizes to any `Iterable<T>`.
- `List`/`Set`/`Map.entries`/ranges are `Iterable`; `asSequence()` accepts any
  `Iterable`.
- **Ranges:** `1..10` (inclusive), `1 until 10`, `10 downTo 1`, `step 2` — each an
  `Iterable<Integer>`, usable in `for` and as sequence sources.

## Other data structures (follow-ons)

Built on the generic core, added as needed: `ArrayDeque<T>` (and `Stack`/`Queue`
over it), `PriorityQueue<T>` (heap, needs `T: Comparable`), sorted/`LinkedHashMap`
when iteration order matters. `T[]` stays the primitive; `MutableList<T>` is the
growable layer over it.

## Phasing

1. **Generics** (monomorphization) — the foundation; also benefits events/channels.
2. **Closures / lambdas** (`=>` and trailing-`{ it }`), capture-by-value.
3. **`std/collections`** — **`List<T>`, `Set<T>`, and `Map<K, V>` shipped**
   (built-in generics: `empty List<T>`/`empty Set<T>`/`empty Map<K, V>`, the
   mutating + query ops, `for x in` over List/Set and `for k in m.keys()`, usable
   as param/field/return). **Ranges, builders, and the core eager functional API shipped** (`a..b`/`until`/`downTo`/`step`; `listOf`/`setOf`/`mapOf`; a broad eager operator set via inlined lambdas: map/filter/filterNot/fold/reduce/sumOf/count/any/all/none/forEach/joinToString/mapIndexed/take/drop/takeWhile/dropWhile/reversed/distinct/flatMap/first/last/toSet). find/firstOrNone/lastOrNone/maxByOrNone/minByOrNone/average too, returning optionals). `sorted`/`groupBy`/`zip` and lazy `Sequence` remain.
4. **`std/sequences`** — lazy fused `Sequence<T>` with the same operators.
5. Extra structures (`ArrayDeque`, `PriorityQueue`, ordered maps) on demand.

## Why this fits the philosophy

- **Fast:** monomorphization + inlined closures + sequence fusion = real zero-cost
  abstractions, the way `T[]` already is.
- **Least dependency:** all generated Ξ/C over libc — no collections runtime.
- **Easy:** a fluent, familiar API — `listOf`, `xs.map { it }`, `asSequence()`,
  ranges — with no lifetimes to learn.

## Open questions

- **Read-only enforcement:** is `List<T>` a genuinely separate interface from
  `MutableList<T>` (compile-time read-only), or one type with a runtime/`val`
  convention? (Leaning: separate interfaces.)
- **Map key bounds:** built-in hashing for primitives/`String` + a `Hashable`
  (`hash()` + `eq()`) interface bound for user keys.
- **`it` and trailing lambdas:** adopt `{ it }` / `{ a, b => ... }`
  trailing-lambda call sugar, or stick to explicit `(x) => ...`?
- **Generic bounds** from day one (needed for `Map` keys / `PriorityQueue`) vs
  later.
- **Destructuring** (`let (k, v) = pair`, `for (k, v) in m`) — include with Pairs?
- **Optional vs Result** in the API: lookups that can miss return `T?` and are
  unwrapped with `if let` (Ξ has no `null` — `none` is the empty optional);
  reserve `Result` (`T!`) for genuine failures.
