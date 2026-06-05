# Standard library

The standard library lives in `std/` as ordinary Xi modules that wrap C runtime
primitives. Import a module and call it through its namespace:

```x
import "std/math.xi"
import "std/text.xi"

async entry main(args: String[]) -> Integer {
    system.stdout.writeln("sqrt(2) = " + math.sqrt(2.0))
    system.stdout.writeln(text.toUpper("hello"))
    return 0
}
```

Import everything at once with `import "std/all.xi"`.

## Resolving imports

`import "std/<mod>.xi"` is resolved first relative to the importing file, then
relative to `$XC_STD` (default `.`, the current directory). Running the compiler
from the project root finds `std/` automatically. To use the library from
elsewhere, point `XC_STD` at the directory that contains `std/`:

```console
$ XC_STD=/path/to/x ./compiler/xc myapp.xi
```

## Modules

### `math` — `std/math.xi`

| Function | Signature |
|----------|-----------|
| `pi`, `e` | `() -> Number` |
| `abs`, `sqrt`, `exp`, `ln`, `log10` | `(Number) -> Number` |
| `sin`, `cos`, `tan` | `(Number) -> Number` |
| `floor`, `ceil`, `round` | `(Number) -> Number` |
| `pow` | `(Number, Number) -> Number` |
| `min`, `max` | `(Number, Number) -> Number` |
| `clamp` | `(Number, Number, Number) -> Number` |

### `text` — `std/text.xi`

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

### `bytes` — `std/bytes.xi`

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

### `convert` — `std/convert.xi`

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

### `json` — `std/json.xi`

Xi's **serialization** library. `Json` is an opaque value tree; build it with the
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

### `yaml` — `std/yaml.xi`

YAML over the same `Json` tree (block style). See [Serialization](serialization.md).

| Function | Signature |
|----------|-----------|
| `stringify` | `(Json) -> String` |
| `parse` | `(String) -> Json` |

### `xml` — `std/xml.xi`

XML over the same `Json` tree (object → child elements, array → repeated element,
scalar → text). See [Serialization](serialization.md).

| Function | Signature |
|----------|-----------|
| `stringify` | `(Json) -> String` (wraps in `<root>`) |
| `stringifyAs` | `(Json, String) -> String` (custom root tag) |
| `parse` | `(String) -> Json` |

### `crypto` — `std/crypto.xi`

Self-contained hashing, HMAC, encodings, and a CSPRNG — no external libraries.
Digests are `Bytes`; render with `hex`/`base64`. (Test-vector verified.)

| Function | Signature |
|----------|-----------|
| `sha256` / `sha1` / `md5` | `(Bytes) -> Bytes` (digest) |
| `sha256Hex` / `sha1Hex` / `md5Hex` | `(String) -> String` (hex digest of text) |
| `hmacSha256` | `(Bytes, Bytes) -> Bytes` (key, msg) |
| `hmacSha256Hex` | `(String, String) -> String` |
| `hex` / `fromHex` | `(Bytes) -> String` / `(String) -> Bytes` |
| `base64` / `fromBase64` | `(Bytes) -> String` / `(String) -> Bytes` |
| `randomBytes` / `randomHex` | `(Integer) -> Bytes` / `(Integer) -> String` (from `/dev/urandom`) |

### `web` — `std/web.xi`

A tiny **REST framework** over HTTP/1.1: implement `WebRequestHandler`, route by
overloading `handle` with `where` guards, and run `web.serve`. Payloads
auto-(de)serialize via a `WebTransport` (JSON by default). See [Web](web.md).

| Name | Kind / Signature |
|------|------------------|
| `WebRequestHandler` | interface — `action handle(req: HttpRequest, res: HttpResponse)` |
| `WebTransport` | interface — `serialize(Json) -> String` / `deserialize(String) -> Json` (JSON default) |
| `req.path` / `req.method` / `req.body` | `HttpRequest -> String` |
| `req.query("q")` / `req.header("X")` | `(HttpRequest, String) -> String` |
| `req.parse(T)` | deserialize the body into a `T` |
| `res.send(dto)` | serialize `dto` and reply `200` |
| `res.sendStatus(code, msg)` / `res.sendText(code, body)` | plain-text reply |
| `web.serve` | `(Integer)` — run a blocking HTTP/1.1 server |

### `thread` — `std/thread.xi`

**Share-nothing threads + channels.** A `parallel` block runs on a new OS thread
and yields a `Thread` handle; threads communicate only through thread-safe
channels (string payloads, copied across the boundary). See [Threading](threading.md).

| Name | Kind / Signature |
|------|------------------|
| `thread.channel()` | `() -> Channel` (thread-safe FIFO) |
| `ch.send(s)` / `ch.recv()` / `ch.close()` | `(Channel, String)` / `(Channel) -> String` (blocks) / `(Channel)` |
| `parallel [(caps…)] { … }` | spawn a thread, evaluates to a `Thread` (captures must be channels) |
| `thread.stopped()` | `() -> Bool` — inside a block, has stop been requested? |
| `t.stop()` / `t.wait()` / `t.running()` | request stop / join / `Bool` liveness |

### `events` — `std/events.xi`

Built-in **typed publish/subscribe**. A producer publishes any DTO under a topic
through an injected `PublisherService`; a `listener` subscribes to a topic and
receives the **typed DTO** — no JSON. The default `MemoryBus`/`MemoryConsumer`
queue events in memory and pass the typed value through without serialization;
bind your own transport to go external (serialize on publish, deserialize on
receive). See [Events](events.md).

| Name | Kind / Signature |
|------|------------------|
| `event T { … }` | a typed event DTO (publishable; gets a derived codec) |
| `events.publish(topic, dto)` | publish any DTO under a topic (via `PublisherService`) |
| `listener f(e: T) on "topic"` | typed subscriber for a topic |
| `PublisherService` | `interface { producer publish(e: Event) }` — outbound transport |
| `ConsumerService` | `interface { consumer run() }` — the delivery pump |
| `MemoryBus` / `MemoryConsumer` | defaults: in-memory queue, no serialization |
| `Events.run()` | run the pump (resolve + run the `ConsumerService`) |
| `Events.dispatch(e)` | deliver an envelope to its typed listeners |
| `Events.encode(e)` / `Events.decode(topic, type, json)` | codec helpers for transports |
| `Events.topic(e)` / `Events.type(e)` | envelope accessors |

### `io` — `std/io.xi`

| Function | Signature |
|----------|-----------|
| `println`, `print`, `eprintln` | `consumer (String)` |
| `readLine` | `() -> String` |
| `eof` | `predicate ()` |

### `fs` — `std/fs.xi`

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

### `path` — `std/path.xi`

Pure-Xi path string helpers (no I/O).

| Function | Signature |
|----------|-----------|
| `join` | `(String, String) -> String` |
| `dirname` | `(String) -> String` (`"."` if none) |
| `basename` | `(String) -> String` |
| `ext` | `(String) -> String` (incl. dot, `""` if none) |
| `stripExt` | `(String) -> String` |

### `net` — `std/net.xi`

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

### `http` — `std/http.xi`

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
import "std/http.xi"
let r = http.get("http://example.com/")
if isOk(r) {
    system.stdout.writeln("status " + r.value.status)
    system.stdout.writeln(r.value.body)
}
```

### `proc` — `std/process.xi`

| Function | Signature |
|----------|-----------|
| `env` | `(String) -> String` (empty if unset) |
| `envOr` | `(String, String) -> String` |
| `run` | `(String) -> Integer` (shell command exit) |
| `exit` | `consumer (Integer)` |

### `time` — `std/time.xi`

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
