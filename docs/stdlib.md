# Standard library

The standard library lives in `std/` as ordinary X modules that wrap C runtime
primitives. Import a module and call it through its namespace:

```x
import "std/math.x"
import "std/text.x"

async entry main(args: String[]) -> Integer {
    system.stdout.writeln("sqrt(2) = " + math.sqrt(2.0))
    system.stdout.writeln(text.toUpper("hello"))
    return 0
}
```

Import everything at once with `import "std/all.x"`.

## Resolving imports

`import "std/<mod>.x"` is resolved first relative to the importing file, then
relative to `$XC_STD` (default `.`, the current directory). Running the compiler
from the project root finds `std/` automatically. To use the library from
elsewhere, point `XC_STD` at the directory that contains `std/`:

```console
$ XC_STD=/path/to/x ./compiler/xc myapp.x
```

## Modules

### `math` — `std/math.x`

| Function | Signature |
|----------|-----------|
| `pi`, `e` | `() -> Number` |
| `abs`, `sqrt`, `exp`, `ln`, `log10` | `(Number) -> Number` |
| `sin`, `cos`, `tan` | `(Number) -> Number` |
| `floor`, `ceil`, `round` | `(Number) -> Number` |
| `pow` | `(Number, Number) -> Number` |
| `min`, `max` | `(Number, Number) -> Number` |
| `clamp` | `(Number, Number, Number) -> Number` |

### `text` — `std/text.x`

| Function | Signature |
|----------|-----------|
| `length` | `(String) -> Integer` |
| `charAt` | `(String, Integer) -> Integer` (code point, `-1` out of range) |
| `substring` | `(String, Integer, Integer) -> String` |
| `trim`, `toUpper`, `toLower` | `(String) -> String` |
| `startsWith`, `endsWith`, `contains` | `predicate (String, String)` |
| `indexOf` | `(String, String) -> Integer` (`-1` if absent) |
| `repeat` | `(String, Integer) -> String` |
| `replace` | `(String, String, String) -> String` (all occurrences) |
| `isEmpty` | `predicate (String)` |

### `bytes` — `std/bytes.x`

`Bytes` is a primitive type: a raw byte buffer, distinct from `String`. Like
`String` it is an immutable value (copies share the buffer; producers
heap-allocate a fresh one). Used for binary I/O.

| Function | Signature |
|----------|-----------|
| `length` | `(Bytes) -> Integer` |
| `at` | `(Bytes, Integer) -> Integer` (byte `0..255`, `-1` out of range) |
| `slice` | `(Bytes, Integer, Integer) -> Bytes` (`[from, to)`) |
| `concat` | `(Bytes, Bytes) -> Bytes` |
| `fromString` | `(String) -> Bytes` |
| `toString` | `(Bytes) -> String` |
| `empty` | `() -> Bytes` |
| `isEmpty` | `predicate (Bytes)` |

### `convert` — `std/convert.x`

| Function | Signature |
|----------|-----------|
| `toString` | `(Number) -> String` |
| `intToString` | `(Integer) -> String` |
| `boolToString` | `(Bool) -> String` |
| `parseNumber` | `(String) -> Number!` |
| `parseInteger` | `(String) -> Integer!` |

`parseNumber`/`parseInteger` return a [result](error-handling.md):

```x
let r = convert.parseInteger("42")
if isOk(r) { system.stdout.writeln("got " + r.value) }
```

### `json` — `std/json.x`

X's **serialization** library. `Json` is an opaque value tree; build it with the
constructors, compose with `set`/`push`, render with `stringify`/`pretty`, and
read text back with `parse`. See [Serialization](serialization.md) for the full
guide.

| Function | Signature |
|----------|-----------|
| `nul` | `() -> Json` |
| `of` | `(Bool) -> Json` |
| `num` / `int` | `(Number) -> Json` / `(Integer) -> Json` |
| `str` | `(String) -> Json` |
| `array`, `object` | `() -> Json` |
| `push` | `(Json, Json) -> Json` (append to array; returns it) |
| `set` | `(Json, String, Json) -> Json` (set object key; returns it) |
| `stringify`, `pretty` | `(Json) -> String` |
| `parse` | `(String) -> Json` (check with `isValid`) |
| `isValid` | `predicate (Json)` |
| `kind`, `length` | `(Json) -> Integer` |
| `isNull` … `isObject` | `predicate (Json)` |
| `at` | `(Json, Integer) -> Json` (array element) |
| `get`, `has`, `keyAt` | object access |
| `asString`, `asNumber`, `asBool` | leaf coercion |
| `getString`, `getNumber` | `(Json, String) -> …` (field shortcut) |

### `events` — `std/events.x`

Built-in **publish/subscribe**. Producers depend on `PublisherService` and call
`publish(topic, payload)`; `listener` methods subscribe with `on "topic"` and
receive an `Event` (`{ topic: String, payload: Json }`). The default `LocalBus`
dispatches synchronously in-process; bind a different `PublisherService` to swap
transport. See [Events](events.md).

| Name | Kind / Signature |
|------|------------------|
| `event T { … }` | a typed event; `Events.emit(T{…})` dispatches it (no serialization) |
| `listener f(e: T)` | typed subscriber (the parameter type is the channel) |
| `Events.emit(value)` | built-in: typed in-process dispatch (+ external if a transport is bound) |
| `Events.deliver(topic, json)` | built-in: inbound router (deserialize → typed dispatch) |
| `Event` | `type { topic: String, payload: Json }` (string-topic tier) |
| `PublisherService` | `interface { producer publish(String, Json) }` (outbound transport) |
| `LocalBus` | default `PublisherService` (in-process, synchronous) |
| `ConsumerService` | inbound transport seam (`consumer run()`) |
| `listener f(e: Event) on "topic"` | string-topic subscriber (`.*` = prefix) |

### `io` — `std/io.x`

| Function | Signature |
|----------|-----------|
| `println`, `print`, `eprintln` | `consumer (String)` |
| `readLine` | `() -> String` |
| `eof` | `predicate ()` |

### `fs` — `std/fs.x`

| Function | Signature |
|----------|-----------|
| `exists`, `isDir`, `isFile` | `predicate (String)` |
| `readFile` | `(String) -> String!` (Err if missing) |
| `readBytes` | `(String) -> Bytes!` (Err if missing) |
| `writeFile` | `(String, String) -> Bool` |
| `writeBytes` | `(String, Bytes) -> Bool` |
| `appendLine` | `(String, String) -> Bool` |
| `size` | `(String) -> Integer!` (bytes; Err if missing) |
| `modifiedTime` | `(String) -> Integer!` (epoch seconds) |
| `remove`, `mkdir`, `mkdirAll` | `(String) -> Bool` |
| `rename`, `copy` | `(String, String) -> Bool` |
| `cwd` | `() -> String` |
| `listDir` | `(String) -> String[]` (names; empty if not a dir) |

### `path` — `std/path.x`

Pure-X path string helpers (no I/O).

| Function | Signature |
|----------|-----------|
| `join` | `(String, String) -> String` |
| `dirname` | `(String) -> String` (`"."` if none) |
| `basename` | `(String) -> String` |
| `ext` | `(String) -> String` (incl. dot, `""` if none) |
| `stripExt` | `(String) -> String` |

### `net` — `std/net.x`

Blocking TCP sockets, client and server. `Conn` and `Listener` wrap a socket
file descriptor. Data is sent/received as `Bytes` (with `*Text` convenience
helpers). Listen on port `0` for an OS-assigned port, then read it with `port`.

| Function | Signature |
|----------|-----------|
| `dial` | `(String, Integer) -> Conn!` (host, port) |
| `listen` | `(Integer) -> Listener!` |
| `accept` | `(Listener) -> Conn!` (blocks) |
| `port` | `(Listener) -> Integer` |
| `send` / `recv` | `(Conn, Bytes) -> Integer` / `(Conn, Integer) -> Bytes` |
| `sendText` / `recvText` | `(Conn, String) -> Integer` / `(Conn, Integer) -> String` |
| `close` | `consumer (Conn)` |
| `closeListener` | `consumer (Listener)` |

### `http` — `std/http.x`

A minimal HTTP/1.1 client over `net` (plain `http://` only — no TLS). A
`Response` is `{ status: Integer, headers: String, body: String }`, where
`headers` is the raw CRLF-separated header block; look one up with `header`.

| Function | Signature |
|----------|-----------|
| `get` | `(String) -> Response!` |
| `post` | `(String, String, String) -> Response!` (url, body, contentType) |
| `request` | `(String, String, String, String) -> Response!` (method, url, body, contentType) |
| `header` | `(Response, String) -> String` (case-insensitive; `""` if absent) |
| `parseUrl` | `(String) -> Url!` (`{host, port, path}`; rejects `https://`) |
| `parseResponse` | `(String) -> Response!` |

```x
import "std/http.x"
let r = http.get("http://example.com/")
if isOk(r) {
    system.stdout.writeln("status " + r.value.status)
    system.stdout.writeln(r.value.body)
}
```

### `proc` — `std/process.x`

| Function | Signature |
|----------|-----------|
| `env` | `(String) -> String` (empty if unset) |
| `envOr` | `(String, String) -> String` |
| `run` | `(String) -> Integer` (shell command exit) |
| `exit` | `consumer (Integer)` |

### `time` — `std/time.x`

| Function | Signature |
|----------|-----------|
| `nowNanos`, `nowMillis` | `() -> Integer` (monotonic) |
| `sleepMs` | `consumer (Integer)` |

## How it's built

Each module declares the C primitives it needs via `extern "C"` (e.g.
`xstd_sqrt`, `xstd_trim`) and exposes a clean, namespaced API. The primitives
live in `runtime/runtime.c`. Because modules use `namespace`, two modules can
expose the same short name without colliding — see
[Multi-file projects](multi-file.md).

!!! note "Collections"
    Generic containers (`List<T>`, `Map<K,V>`) await generics (monomorphization)
    and are not in the library yet. Use `T[]` arrays with `for … in` for now.
