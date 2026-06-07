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
- See `examples/collections_demo.xi`.

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
```

Lookups that can miss return an **optional** (`T?`), unwrapped with `if let`
(there's no `null`):

```x
if let hit = nums.find { it > 4 } { use(hit) }   // first match, or none
nums.firstOrNone()  / nums.lastOrNone()          // ends as optionals
nums.maxByOrNone { it.score }                    // element with the max key
nums.minByOrNone { it.score }                    // element with the min key
nums.average { it.score }                        // Number mean (0.0 if empty)
```

They chain naturally — `orders.filter { it.paid }.map { it.qty }.fold(0) { a, b => a + b }`.
See `examples/functional_demo.xi`.

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

## What's next

`List<T>`, `Set<T>`, and `Map<K, V>` are in — the core containers. The rich
functional API (`map` / `filter` / `fold` / …) and lazy sequences build on
**closures**, a separate language feature; see the
[collections proposal](proposals/collections.md) for the full design.
