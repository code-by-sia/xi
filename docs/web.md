# Web (`WebRequestHandler` & `std/web`)

`std/web` is a small REST framework over HTTP/1.1. You write **controllers** —
classes that implement the **`WebRequestHandler`** interface — and route by
overloading its `handle` method with `where` guards. Payloads are
(de)serialized automatically — there is no manual JSON.

```x
import "std/web.xi"
```

## Controllers

A controller is any class that `implements WebRequestHandler`. The contract is one
`action` method — `action` is an impure function kind: it may mutate, and is not
a pure function. Route by writing several `handle` overloads, each guarded with
`where`; the first matching overload wins.

**Controllers are auto-registered** — every class implementing
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

### Mount prefix — `getBaseUrl`

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
**interface default method** — any interface method may carry a `{ … }` body that
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

## The `HttpResponse`

The response is *mutable* — fill it in, don't return it.

| Method | Effect |
|--------|--------|
| `res.send(dto)` | serialize `dto` via the `WebTransport` and reply `200` |
| `res.sendStatus(code, msg)` | reply `code` with a plain-text `msg` |
| `res.sendText(code, body)` | reply `code` with a plain-text body |

`res.send` / `req.parse` work for any `event` or compound `type`; the compiler
derives the codec automatically. A request that no controller matches gets a
`404`.

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
program still compiles everywhere). Everything else — controllers, `res.send`,
`WebTransport` — is identical to plaintext.

### HTTP/2

`web.serveHttp2(port, cert, key)` runs the same handlers over HTTP/2 (ALPN `h2`,
falling back to HTTP/1.1 for clients that don't negotiate it). Build with
`XC_HTTP2=1`, which links OpenSSL **and** nghttp2:

```console
$ XC_HTTP2=1 xc app.xi && ./build/app
web: serving HTTP/2 on https://0.0.0.0:8443
$ curl --http2 -k https://localhost:8443/health    # negotiates h2 via ALPN
```

HTTP/3 (QUIC) is not yet available — it needs a QUIC stack; see the
[web-stack proposal](proposals/web-stack.md).

## Notes & limits

- HTTP/1.1, blocking, one request per connection (no keep-alive) — fine for an
  API behind a reverse proxy; concurrency and keep-alive are future work.
- Routing is by exact `req.path` match in `where` guards. There is no path-pattern
  capture (`/users/:id`); read sub-paths from `req.path` or use query parameters.
- HTTPS needs OpenSSL at build time (`XC_TLS=1`). **HTTP/2 / HTTP/3** are still
  planned — see the [web-stack proposal](proposals/web-stack.md).
- No `%`-decoding of query values yet; no multipart parsing.

See `examples/web_demo.xi`.
