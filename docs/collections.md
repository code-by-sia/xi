# Collections

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
