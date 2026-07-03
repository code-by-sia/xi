# Serialization (`std/json`)

Xi serializes data through **JSON**. The `std/json` module gives you a `Json`
value tree you can build in code, render to text, and parse back. It is the
foundation for anything that crosses a boundary — files, sockets, HTTP bodies,
and external [event](events.md) transports.

```x
import "std/json.xi"
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

## Automatic derive

Wherever the compiler sees a (de)serialization boundary it **derives the codec
from the type's fields** — no hand-written mapping, nested types included:

- **`<json> as T`** reconstructs any compound type from a `Json` tree, so reading
  a value is just `let u = json.parse(text) as User`.
- **Web** replies and bodies: `res.send(dto)` and `req.parse(T)` — see [web](web.md).
- **Event** transports and typed **`readConfig`** — see [events](events.md) and
  [config](config.md).

```x
type Address = { city: String, zip: Integer }
type User    = { name: String, age: Integer, addr: Address }

let u = json.parse(body) as User      // whole tree -> nested object, auto-derived
```

## Building a tree by hand

To *produce* a `Json` tree outside those contexts — there is no general
`obj as Json` operator yet — build it explicitly with `std/json`:

```x
mapper userToJson(u: User) -> Json {
    let o = json.object()
    o = json.set(o, "name", json.str(u.name))
    o = json.set(o, "age", json.int(u.age))
    return o
}
```

This is what an **external event transport** does under the hood: an event's
typed payload is turned into `Json` (`stringify`) to leave the process and rebuilt
(`parse`) on the far side — see [Events](events.md). The `std/json` codecs for
`event` types are derived automatically.

## YAML and XML

The `Json` value tree is a **format-agnostic document model**: the same tree can
be rendered as JSON, **YAML** (`std/yaml`), or **XML** (`std/xml`), and parsed
back from any of them. Build/read with `std/json`; pick the wire format at the
edge.

```x
import "std/json.xi"
import "std/yaml.xi"
import "std/xml.xi"

let y = yaml.stringify(person)   // block YAML
let p = yaml.parse(y)            // -> Json (check with json.isValid)

let x = xml.stringify(person)               // wrapped in <root>…</root>
let q = xml.parse("<root><name>Ada</name></root>")   // -> Json (root value)
```

### `yaml` — `std/yaml`

| Function | Signature |
|----------|-----------|
| `stringify` | `(Json) -> String` (block style) |
| `parse` | `(String) -> Json` |

Supports block **mappings**, **sequences**, scalars, nesting, and `#` comments
(including `- key: val` sequences-of-maps). Not supported: flow style (`{}`/`[]`),
anchors/aliases, multi-line scalars, and inline (end-of-line) comments.

### `xml` — `std/xml`

| Function | Signature |
|----------|-----------|
| `stringify` | `(Json) -> String` (wraps in `<root>`) |
| `stringifyAs` | `(Json, String) -> String` (custom root tag) |
| `parse` | `(String) -> Json` (returns the root element's value) |

Convention: an **object** → child elements (one per key); an **array** → a
repeated element; a **scalar** → element text. On parse, repeated tags collect
into an array and leaf text is type-inferred. Entities
(`&lt; &gt; &amp; &quot; &apos;`) are handled. **Attributes are ignored** on parse
and not emitted, and mixed text+element content isn't represented — XML↔JSON is
inherently lossy, so use it for data interchange, not document fidelity.

## Notes & limits

- Three formats today (JSON, YAML, XML) over one `Json` tree; other encoders
  could target it later.
- No streaming parser — `parse` reads a whole string.
- No schema validation; you check shapes yourself with `kind`/`is*`.

See `examples/json_demo.xi` and `examples/yaml_xml_demo.xi`.
