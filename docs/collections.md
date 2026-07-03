# Collections

## Builders

Besides `empty` + mutation, you can construct a populated collection in one
expression. Element/key types are inferred from the first argument (keep the
elements homogeneous):

```x
let xs   = listOf(2, 3, 5, 7)                    // List<Integer>
let tags = setOf("a", "b", "a")                  // Set<String> (deduplicates)
let caps = mapOf("fr" to "Paris", "jp" to "Tokyo")  // Map<String, String>
```

`k to v` pairs the key and value in `mapOf`. For an empty collection, use
`empty List<T>` / `empty Set<T>` / `empty Map<K, V>` (the type can't be inferred
with no elements).

## `List<T>`

`List<T>` is a growable, mutable, typed list — a **built-in generic**, the same
way `T[]` arrays are. There's nothing to import; the compiler specializes it per
element type and the runtime stores elements contiguously, so it's a thin,
allocation-light layer (no boxing).

### Creating one

Use `empty` (the zero/blank-value keyword) with a `List<T>` type:

```x
let nums  = empty List<Integer>
let names = empty List<String>
let items = empty List<Item>          // element can be any type
```

### Operations

```x
nums.push(10)            // append
nums.get(0)              // element at index (bounds-checked; aborts if out of range)
nums.set(0, 99)          // replace element
nums.len()               // Integer count
nums.isEmpty()           // Bool
nums.removeAt(0)         // remove by index (shifts the rest down)
nums.clear()             // empty it
```

Iterate with `for`:

```x
let sum = 0
for n in nums { sum = sum + n }
```

A `List<T>` is a normal value: pass it to functions, store it in fields, return
it.

```x
mapper totalQty(items: List<Item>) -> Integer {
    let sum = 0
    for it in items { sum = sum + it.qty }
    return sum
}
```

### Notes

- A `List<T>` is a **mutable handle** (reference semantics): passing it to a
  function and mutating it is visible to the caller.
- Element access is bounds-checked; an out-of-range `get`/`set`/`removeAt` aborts.
- See `examples/collections/collections_demo.xi`.

## Functional operations on `List<T>`

Lists have a functional API driven by **lambdas**: `{ it ... }` binds the element
implicitly, or `{ a, b => ... }` names the parameters. Each call is inlined into a
loop, so chains are zero-overhead (no intermediate closures).

```x
let nums = listOf(1, 2, 3, 4, 5)

nums.map { it * 2 }                 // List<U> — transform (U is the body's type)
nums.filter { it % 2 == 0 }        // List<T> — keep matching
nums.filterNot { it > 3 }          // List<T> — drop matching
nums.forEach { print(it) }         // run a side effect per element
nums.fold(0) { acc, x => acc + x } // reduce with a seed
nums.reduce { a, b => a + b }      // reduce, seed = first element
nums.sumOf { it }                  // sum of a projection (Integer/Number)
nums.count { it > 2 }              // Integer — how many match
nums.any { it > 4 }                // Bool
nums.all { it > 0 }                // Bool
nums.none { it > 9 }               // Bool
nums.joinToString(", ") { int_to_string(it) }   // String, with a separator

nums.mapIndexed { i, x => i * 10 + x }   // map with the index
nums.take(3) / nums.drop(2)              // first n / skip n
nums.takeWhile { it < 4 }                // prefix while the predicate holds
nums.dropWhile { it < 4 }                // drop that prefix
nums.reversed()                          // reversed copy
nums.distinct()                          // unique elements, order preserved
nums.flatMap { listOf(it, it) }          // map then flatten the result lists
nums.first() / nums.last()               // ends (bounds-checked)
nums.toSet()                             // Set<T> of the elements
nums.toList()                            // a shallow copy
nums.onEach { print(it) }                // side effect per element, returns the list
nums.withIndex()                         // List<Pair<Integer, T>> — index/value pairs
nested.flatten()                         // List<List<T>> -> List<T>
nums.scan(0) { acc, x => acc + x }       // running accumulations, incl. the seed
nums.runningFold(0) { acc, x => acc + x } // alias for scan
```

Whole-list reductions over the elements (numeric or `String`):

```x
nums.sum()                               // numeric total (0 if empty)
nums.min() / nums.max()                  // natural extreme (aborts if empty)
nums.maxOf { it.score } / nums.minOf { it.score }   // extreme of a projection
nums.contains(3)                         // Bool — membership
nums.indexOf(3)                          // Integer — first index, or -1
nums.single { it > 4 }                   // the one match (aborts if 0 or many)
```

Lookups that can miss return an **optional** (`T?`), unwrapped with `if let`
(there's no `null`):

```x
if let hit = nums.find { it > 4 } { use(hit) }   // first match, or none
nums.firstOrNone()  / nums.lastOrNone()          // ends as optionals
nums.minOrNone()    / nums.maxOrNone()           // natural extreme as an optional
nums.singleOrNone { it > 4 }                     // the one match, or none if 0/many
nums.maxByOrNone { it.score }                    // element with the max key
nums.minByOrNone { it.score }                    // element with the min key
nums.average { it.score }                        // Number mean (0.0 if empty)
```

Sorting returns a sorted copy (numeric or `String` keys):

```x
nums.sorted() / nums.sortedDescending()          // natural order of the elements
people.sortedBy { it.age }                        // by a key projection
people.sortedByDescending { it.name }
```

Grouping and slicing into sublists:

```x
people.groupBy { it.team }          // Map<K, List<T>> — bucket by a key
people.associateBy { it.id }        // Map<K, T> — index by a key
items.associateWith { it.price }    // Map<T, V> — element -> value (T is primitive/String)
nums.chunked(3)                     // List<List<T>> — consecutive groups
nums.windowed(3)                    // List<List<T>> — sliding windows
```

`groupBy` results chain: `people.groupBy { it.team }.get("x").average { it.age }`.

### Lazy sequences

`asSequence()` makes the pipeline **lazy**: the chain of lazy operators plus the
terminal compile into a **single fused loop** — no intermediate lists are built,
and `take` short-circuits.

```x
let total = orders.asSequence()
    .filter { it.active }
    .map    { it.total }
    .fold(0.0) { a, b => a + b }     // one loop, no intermediates

nums.asSequence().take(3).sum()      // visits only the first 3 elements
```

- **Lazy ops:** `map`, `filter`, `filterNot`, `take(n)`, `drop(n)`, `takeWhile`,
  `dropWhile`.
- **Terminals:** `toList()`, `toSet()`, `forEach`, `fold(seed)`, `sum()`,
  `count()`, `any`, `all`, `first()`, `firstOrNone()`.

They chain naturally — `orders.filter { it.paid }.map { it.qty }.fold(0) { a, b => a + b }`.
See `examples/collections/functional_demo.xi`.

## Pairs — `Pair<A, B>`

A two-value tuple. Build one with the `to` infix; read the members with `.first`
and `.second`. `A` and `B` can be any types (including lists or other pairs).

```x
let p = "ada" to 36          // Pair<String, Integer>
p.first                      // "ada"
p.second                     // 36
```

Three `List` operations produce or consume pairs:

```x
names.zip(ages)              // List<Pair<String, Integer>> (truncated to the shorter)
nums.partition { it > 0 }    // Pair<List<Integer> matching, List<Integer> not>
pairs.unzip                  // Pair<List<A>, List<B>> — splits a list of pairs back
```

```x
let pairs = listOf("ada", "bo").zip(listOf(36, 28))
for p in pairs { print(p.first + " is " + int_to_string(p.second)) }

let parts = listOf(1, 2, 3, 4).partition { it % 2 == 0 }
parts.first.len()            // 2  (evens)
parts.second.len()           // 2  (odds)

let cols = pairs.unzip
cols.first                   // List<String>  ["ada", "bo"]
cols.second                  // List<Integer> [36, 28]
```

See `examples/collections/pairs_demo.xi`.

## `Set<T>`

`Set<T>` is a hash set of **unique** elements — also a built-in generic, created
with `empty`. Element-type-erased like `List`, with `String` elements compared by
content (not by reference).

### Creating one

```x
let ids   = empty Set<Integer>
let names = empty Set<String>
```

### Operations

```x
ids.add(1)               // insert; idempotent (no-op if already present)
ids.contains(1)          // Bool, O(1) average
ids.remove(1)            // delete (no-op if absent)
ids.len()                // Integer count of unique elements
ids.isEmpty()            // Bool
ids.clear()              // empty it
ids.items()              // a List<T> snapshot of the live elements
```

Iterate with `for` (order is unspecified):

```x
for x in ids { ... }
```

### Notes

- Membership is by **value**: two `String`s with equal content are the same
  element; struct elements are compared by their bytes.
- A `Set<T>` is a mutable handle (reference semantics), like `List<T>`.
- Iteration order is not specified; use `items()` if you need a `List` to sort.

## `Map<K, V>`

`Map<K, V>` is a hash map — a built-in generic, created with `empty`. Keys are
primitives or `String` (compared by value, `String` by content); values can be
any type.

### Creating one

```x
let ages  = empty Map<String, Integer>
let names  = empty Map<Integer, String>
let byId  = empty Map<String, Item>      // value can be a compound
```

### Operations

```x
ages.put("ada", 37)      // insert or overwrite
ages.get("ada")          // value (aborts if the key is absent — guard with has)
ages.getOr("zz", 0)      // value, or the fallback if absent
ages.has("ada")          // Bool
ages.remove("ada")       // delete (no-op if absent)
ages.len()               // Integer entry count
ages.isEmpty()           // Bool
ages.clear()             // empty it
ages.keys()              // a List<K> of the keys
ages.values()            // a List<V> of the values
```

Since lookups can miss, iterate over the keys (no `null` in Ξ — a missing key
is simply not in `keys()`):

```x
for k in ages.keys() {
    let v = ages.get(k)
    ...
}
```

### Notes

- `get` aborts if the key is absent — use `has` to check first, or `getOr` for a
  default. (A `V?`-returning lookup will follow once optionals are wired into the
  collection API.)
- Keys are restricted to primitives and `String`; values may be any type.
- A `Map<K, V>` is a mutable handle (reference semantics). Iteration order is
  unspecified.

## `Vec<T>` — dynamic array

`Vec<T>` is a growable, index-addressable array. It is the **same type as
`List<T>`** under a familiar name, so it has the entire `List` surface — indexing
(`get`/`set`), `push`/`removeAt`, the whole [functional API](#functional-operations-on-listt),
and lazy sequences — plus two array conveniences:

```x
let v = vecOf(1, 2, 4)       // or: empty Vec<Integer>
v.insert(2, 3)               // 1 2 3 4   (shift right; index == len appends)
v.swap(0, 3)                 // 4 2 3 1
v.get(0)  v.set(1, 9)  v.len()  v.push(5)
v.map { it * 2 }.filter { it > 4 }     // the functional pipeline, as on List
```

Because `Vec<T>` and `List<T>` are interchangeable, a value built with `vecOf`
can be passed wherever a `List<T>` is expected, and vice versa.

## `Stack<T>` — LIFO

```x
let s = empty Stack<Integer>     // or: stackOf(1, 2, 3)
s.push(10)                       // add to the top
s.peek()                         // look at the top (aborts if empty)
s.pop()                          // remove & return the top (aborts if empty)
s.len()   s.isEmpty()   s.clear()
```

## `Queue<T>` — FIFO

```x
let q = empty Queue<String>      // or: queueOf("a", "b")
q.enqueue("job")                 // add to the back  (alias: push)
q.peek()                         // look at the front (aborts if empty)
q.dequeue()                      // remove & return the front (aborts if empty)
q.len()   q.isEmpty()   q.clear()
```

Dequeue is amortised O(1) (an internal head index, no per-element shifting).

## `SortedQueue<T>` — priority queue

A binary **min-heap**: `pop`/`peek` always return the **smallest** element by
natural order. Element types are the comparable primitives (`Integer`, `Number`,
`String` by content, `Char`).

```x
let pq = sortedQueueOf(5, 1, 9, 3)   // or: empty SortedQueue<Integer>
pq.push(2)
pq.peek()                            // 1 — the minimum (aborts if empty)
pq.pop()                             // 1, then 2, then 3, ... (ascending)
pq.len()   pq.isEmpty()   pq.clear()
```

> `pop`/`peek`/`dequeue` **abort** on an empty container (like `list.first()`);
> guard with `isEmpty()`/`len()`. These containers are mutable handles (reference
> semantics), like `List`. See `examples/collections/containers_demo.xi`.

## Lazy infinite sources — `generateSequence`

`generateSequence(seed) { next }` is a lazy source whose value starts at `seed`
and advances through the generator each step. It fuses into the sequence loop like
any other source, so it's only as long as the bounded terminal asks for — **always
bound it** with `take`, `takeWhile`, or `first`:

```x
generateSequence(1) { it * 2 }.take(8).toList()        // [1,2,4,…,128]
generateSequence(1) { it + 1 }.take(10).fold(0) { a, b => a + b }   // 55
generateSequence(0) { it + 2 }.takeWhile { it < 10 }.toList()      // [0,2,4,6,8]
```

See `examples/collections/generate_sequence_demo.xi`.

## What's next

The collection layer is complete: containers (`List`/`Vec`/`Set`/`Map`,
`Stack`/`Queue`/`SortedQueue`), the eager functional API, lazy sequences (incl.
`generateSequence`), `Pair<A, B>`, and `zip`/`partition`/`unzip`. For fixed-size
**math vectors** (Vec2/Vec3/Vec4 with dot/cross/normalize/…) see the `std/vec`
module and `examples/collections/vec_math_demo.xi`.
[First-class closures](language-guide.md#first-class-functions-closures)
now ship (single typed param, capture-free); multi-parameter lambdas, captures,
and generics are the remaining language-level work (see `FEATURES.md`).
