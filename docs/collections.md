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

## What's next

`List<T>` is the first piece. `Map<K, V>` / `Set<T>`, the rich functional API
(`map` / `filter` / `fold` / …), and lazy sequences are planned — they build on
generics and closures; see the
[collections proposal](proposals/collections.md) for the full design.
