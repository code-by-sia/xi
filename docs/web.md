# Web (`WebRequestHandler` & `std/web`)

`std/web` is a small REST framework over HTTP/1.1. You write **controllers** -
classes that implement the **`WebRequestHandler`** interface - and route by
overloading its `handle` method with `where` guards. Payloads are
(de)serialized automatically - there is no manual JSON.

```x
import "std/web.xi"
```

## Controllers

A controller is any class that `implements WebRequestHandler`. The contract is one
`action` method - `action` is an impure function kind: it may mutate, and is not
a pure function. Route by writing several `handle` overloads, each guarded with
`where`; the first matching overload wins.

**Controllers are auto-registered** - every class implementing
`WebRequestHandler` is discovered and DI-wired automatically, with no `bind`.
Split routes across as many controllers as you like; the server tries each (in
declaration order) and the first overload whose guard matches handles the
request. An unmatched request falls through to a `404`.

```x
event Health { ok: Bool }
event User   { name: String, active: Bool }

class HealthController implements WebRequestHandler {
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/health" {
        res.send(Health { ok: true })
    }
}

class UserController implements WebRequestHandler {
    deps { repo: Repo }                                   // injected, as usual

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/user" {
        let name = req.query("name")
        res.send(User { name: name, active: repo.active(name) })
    }
}

module App {}                                             // no bind needed
```

A controller whose guards don't match simply leaves the response untouched, so
the next controller gets a turn. (An un-guarded `handle` overload always matches,
so use one only as a deliberate catch-all, and declare that controller last.)

### Mount prefix - `getBaseUrl`

`WebRequestHandler` also has a `getBaseUrl()` method with a **default
implementation** returning `"/"`; the server only consults a controller when the
request path starts with it. Override it to mount a controller under a prefix:

```x
class ApiController implements WebRequestHandler {
    mapper getBaseUrl() -> String { return "/api/v1" }   // only sees /api/v1/*
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/api/v1/stats" {
        res.send(stats())
    }
}
```

(`where` guards still compare the full `req.path`.) `getBaseUrl` is an ordinary
**interface default method** - any interface method may carry a `{ … }` body that
implementors inherit unless they override it.

## The `HttpRequest`

| Accessor | Returns |
|----------|---------|
| `req.path` | the request path |
| `req.method` | the HTTP method (`"GET"`, …) |
| `req.body` | the raw body as a `String` |
| `req.query("q")` | a `?q=…` query value (`""` if absent) |
| `req.header("X")` | a request header (case-insensitive; `""` if absent) |
| `req.parse(T)` | the body **deserialized** into a `T` via the `WebTransport` |

## Path patterns + typed extraction

For routes with path parameters, route on **method + a `/users/:id` pattern** and
pull each source out as its own typed value. `web.route` captures the `:params`;
the four source getters each return a flat `Json` you decode with `as T`:

| Call | Returns |
|------|---------|
| `web.route(req, "POST", "/users/:id")` | `Bool` - method+pattern match (use as a `where` guard; captures `:params`) |
| `web.params(req)` | path params as `Json` |
| `web.query(req)` | query string as `Json` |
| `web.headers(req)` | headers as `Json` (names normalized: `Content-Type` → `content_type`) |
| `web.body(req)` | the parsed body as `Json` |

`json as T` decodes a `Json` into any compound `type`, coercing string scalars -
so a `"42"` path segment becomes an `Integer` and `"true"` a `Bool`:

```x
type IdRef   = { id: Integer }
type NewUser = { name: String, email: String }
type Auth    = { authorization: String }

action handle(req, res) where web.route(req, "POST", "/users/:id") {
    let ref  = web.params(req)  as IdRef       // path   -> typed
    let body = web.body(req)    as NewUser     // body   -> typed
    let auth = web.headers(req) as Auth        // header -> typed
    res.send(create(ref.id, body.name, auth.authorization))
}
```

Each source is decoded independently into the shape you want - no envelope, no
merge order. `as T` is a general decode (it also works on any `Json`, e.g. from
`json.parse`), so nothing about HTTP leaks into the language. See
`examples/web/web_params_demo.xi`.

`capture` pairs nicely here: name a value computed inside the guard (e.g. an
order total) and reuse it in the body and the response -
`if lineTotal(order) capture total: Integer > 0 { … res.send(Receipt { total: total }) }`.
See [`capture`](language-guide.md#capture---name-a-sub-expressions-value) and
`examples/web/web_capture_demo.xi`.

## The `HttpResponse`

The response is *mutable* - fill it in, don't return it.

| Method | Effect |
|--------|--------|
| `res.send(dto)` | serialize `dto` via the `WebTransport` and reply `200` |
| `res.sendStatus(code, msg)` | reply `code` with a plain-text `msg` |
| `res.sendText(code, body)` | reply `code` with a plain-text body |

`res.send` / `req.parse` work for any `event` or compound `type`; the compiler
derives the codec automatically. The payload can also be a **bare `List<T>` or
`T[]`** - it serializes to a JSON array, so a controller can return a
repository's list directly with no wrapper DTO:

```x
action handle(req: HttpRequest, res: HttpResponse) {
    res.send(users.findAll())      // -> [ {...}, {...} ]  (List<User>)
}
```

A `List<T>` field on a DTO works the same way, and is stored growably in memory,
so a service can accumulate posted items and hand the list straight back. A
request that no controller matches gets a `404`.

### Keeping state across requests

A service that accumulates data across requests must be a **singleton** so every
request shares one instance - either mark the dependency at the injection site
or bind it in the module:

```x
class ItemStore implements Store {
    state { items: List<Item> = empty List<Item> }
    consumer add(it: Item) { this.items.push(it) }
    ...
}

class ItemController implements WebRequestHandler {
    deps { store: Store as singleton }                // marker: one shared store
    ...
}
// - or, equivalently, in the module -
module App { bind Store -> ItemStore as singleton }
```

Left transient (the default), the service is resolved fresh each request and its
state never accumulates. See `examples/web/web_store_demo.xi` for the full
pattern.

## The `WebTransport`

`res.send(dto)` and `req.parse(T)` route through the bound `WebTransport`, which
maps a value to/from the wire body. The default is JSON:

```x
interface WebTransport {
    mapper serialize(payload: Json) -> String
    mapper deserialize(body: String) -> Json
}
```

Bind your own implementor (e.g. a different wire format) to replace it:

```x
module App {
    bind WebTransport -> MsgPackTransport   // overrides the JSON default
}
```

## Running

```x
async entry main(args: String[]) -> Integer {
    web.serve(8080)        // blocking HTTP/1.1 server
    return 0
}
```

```console
$ xc app.xi && ./build/app
web: serving on http://0.0.0.0:8080
```

`web.serve` blocks until the server is stopped. **`web.shutdown()`** stops it -
it unblocks `serve` so the call returns and the process exits. It is safe to call
from another thread, so a background timer can bound the server's lifetime (the
serve demos use this so a run never blocks):

```x
async entry main(args: String[]) -> Integer {
    runWithDelay(30000) { web.shutdown() }   // self-terminate after 30s
    web.serve(8080)
    return 0
}
```

## HTTPS

`web.serveTLS(port, certPath, keyPath)` runs the same handler stack over TLS.
TLS is **opt-in** so default builds stay dependency-light: compile the program
with `XC_TLS=1`, which links the platform's OpenSSL.

```x
async entry main(args: String[]) -> Integer {
    web.serveTLS(8443, "cert.pem", "key.pem")   // PEM cert + private key
    return 0
}
```

```console
$ XC_TLS=1 xc app.xi && ./build/app
web: serving on https://0.0.0.0:8443
```

Built without `XC_TLS`, `serveTLS` prints a notice and serves nothing (so the
program still compiles everywhere). Everything else - controllers, `res.send`,
`WebTransport` - is identical to plaintext.

### HTTP/2

`web.serveHttp2(port, cert, key)` runs the same handlers over HTTP/2 (ALPN `h2`,
falling back to HTTP/1.1 for clients that don't negotiate it). Build with
`XC_HTTP2=1`, which links OpenSSL **and** nghttp2:

```console
$ XC_HTTP2=1 xc app.xi && ./build/app
web: serving HTTP/2 on https://0.0.0.0:8443
$ curl --http2 -k https://localhost:8443/health    # negotiates h2 via ALPN
```

HTTP/3 (QUIC) is not yet available - it needs a QUIC stack (`ngtcp2`/`quiche`),
which isn't broadly installed and has no common client to test against; it's the
one open transport.

## Notes & limits

- HTTP/1.1, blocking, one request per connection (no keep-alive) - fine for an
  API behind a reverse proxy; concurrency and keep-alive are future work.
- Routing supports exact `req.path` matches **and** path-pattern capture via
  `web.route(req, method, "/users/:id")` - including multiple parameters
  (`/foo/:id/bar/:second`), adjacent (`/x/:a/:b`) and leading (`/:a/foo/:b`)
  params. Captured `:params` are read with `web.params(req) as T`.
- HTTPS / HTTP/2 need OpenSSL (and nghttp2) at build time (`XC_TLS=1` /
  `XC_HTTP2=1`). **HTTP/3** is the one remaining transport (QUIC).
- No `%`-decoding of query values yet; no multipart parsing.
- A request (headers + body) is capped at **32 MB**; larger ones, and a
  `Content-Length` above that, are dropped rather than buffered. JSON parsing
  rejects nesting deeper than **200** levels, so an untrusted body cannot
  exhaust the stack. Both limits return an error rather than failing the process.

  Tune either per service with an environment variable:

  | Variable | Default | Effect |
  |---|---|---|
  | `XI_MAX_REQUEST` | `33554432` (32 MB) | largest buffered request, in bytes (floor 64 KB) |
  | `XI_JSON_MAX_DEPTH` | `200` | deepest JSON nesting accepted (clamped to 16..10000) |

  Raise `XI_MAX_REQUEST` for an endpoint that takes large uploads, or lower it to
  tighten the blast radius of a hostile client. Values are read once at first use
  and clamped, so a mistaken setting cannot disable the guard.

See `examples/web/web_demo.xi`.
