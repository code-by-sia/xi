# Serialization (`std/json`)

Ξ serializes data through **JSON**. The `std/json` module gives you a `Json`
value tree you can build in code, render to text, and parse back. It is the
foundation for anything that crosses a boundary — files, sockets, HTTP bodies,
and external [event](events.md) transports.

```x
import "std/json.x"
```

## The `Json` value

`Json` is an opaque, immutable-feeling handle to a node in a value tree. A node is
one of six kinds: **null, bool, number, string, array, object**. You never
construct one directly — you use the module's constructors:

```x
json.nul()             // null
json.of(true)          // bool
json.num(3.14)         // number (from Number)
json.int(36)           // number (from Integer)
json.str("hello")      // string
json.array()           // [] — fill with push
json.object()          // {} — fill with set
```

## Building

`push` appends to an array and `set` assigns an object key; both **return the
container**, so you can keep a running value:

```x
let langs = json.array()
langs = json.push(langs, json.str("X"))
langs = json.push(langs, json.str("C"))

let person = json.object()
person = json.set(person, "name", json.str("Ada"))
person = json.set(person, "age", json.int(36))
person = json.set(person, "langs", langs)       // nest freely
```

## Serializing

```x
json.stringify(person)
// {"name":"Ada","age":36,"langs":["X","C"]}

json.pretty(person)
// {
//   "name": "Ada",
//   "age": 36,
//   "langs": [
//     "X",
//     "C"
//   ]
// }
```

`stringify` produces compact output (for the wire); `pretty` indents (for humans
and logs). Strings are escaped; numbers print as integers when they have no
fractional part.

## Parsing

`parse` turns text into a `Json` tree. Malformed input doesn't crash — it yields
a value that fails `isValid`:

```x
let v = json.parse(body)
if not json.isValid(v) {
    system.stderr.writeln("bad json")
    return 1
}
```

Then read it. Object/array access never traps — a missing key or out-of-range
index returns a `null` node, and the `as*` coercions return a zero value on a
kind mismatch:

```x
json.getString(v, "city")        // "" if absent or not a string
json.getNumber(v, "pop")         // 0  if absent or not a number

let tags = json.get(v, "tags")   // a Json (array)
let n    = json.length(tags)     // element count
let t0   = json.asString(json.at(tags, 0))
```

For finer control, branch on `kind` (or the `is*` predicates) and walk objects by
index with `keyAt` + `get`:

```x
if json.isObject(v) {
    let i = 0
    while i < json.length(v) {
        let k = json.keyAt(v, i)
        system.stdout.writeln(k + " = " + json.stringify(json.get(v, k)))
        i = i + 1
    }
}
```

## Encoding your own types

There is no automatic derive yet (it awaits compile-time reflection), so write a
small `toJson` / `fromJson` pair per type — a few lines, and explicit:

```x
type User = { name: String, age: Integer }

mapper userToJson(u: User) -> Json {
    let o = json.object()
    o = json.set(o, "name", json.str(u.name))
    o = json.set(o, "age", json.int(u.age))
    return o
}

mapper userFromJson(v: Json) -> User {
    return User { name: json.getString(v, "name"),
                  age: 0 + json.getNumber(v, "age") }
}
```

This is what an **external event transport** does under the hood: an event's
typed payload is turned into `Json` (`stringify`) to leave the process and rebuilt
(`parse`) on the far side — see [Events](events.md). The `std/json` codecs for
`event` types are derived automatically.

## Notes & limits

- One serialization format today (JSON). The `Json` tree is format-agnostic
  enough that other encoders (e.g. a compact binary form) could target it later.
- No streaming parser — `parse` reads a whole string.
- No schema validation; you check shapes yourself with `kind`/`is*`.

See `examples/json_demo.x`.
