# Web (`route` & `std/web`)

`std/web` is a small REST framework over HTTP/1.1. You write request handlers as
**`route`** methods — a function kind, auto-discovered and dependency-injected
like any service — and run a server with `web.serve`.

```x
import "std/web.xi"
import "std/json.xi"
```

## A handler

A `route` lives in a class (so it can declare `deps`). It names its HTTP method
and path with `on <method> "<path>"`, takes a `Request`, and returns a `Response`:

```x
interface Repo { mapper name(id: String) -> String }

class Api {
    deps { repo: Repo }                                  // injected, as usual

    route user(req: Request) -> Response on get "/users/:id" {
        let o = json.object()
        o = json.set(o, "id",   json.str(web.param(req, "id")))   // :id path param
        o = json.set(o, "name", json.str(repo.name(web.param(req, "id"))))
        return web.json(200, o)
    }
}
```

Routes are discovered automatically (the same machinery as event `listener`s); a
generated router matches each request's method + path and calls the handler on a
freshly DI-resolved instance.

## The `Request`

| Accessor | Returns |
|----------|---------|
| `web.method(req)` | the HTTP method (`"GET"`, …) |
| `web.path(req)` | the request path |
| `web.param(req, "id")` | a `:id` **path** segment |
| `web.query(req, "q")` | a `?q=…` **query** value (`""` if absent) |
| `web.header(req, "X")` | a request header (case-insensitive; `""` if absent) |
| `web.body(req)` | the raw body as a `String` |
| `web.bodyJson(req)` | the body parsed as a [`Json`](serialization.md) value |

Path patterns use `/literal/:param` segments; `:param` captures into `web.param`.

## The `Response`

| Builder | Result |
|---------|--------|
| `web.text(status, body)` | `text/plain` |
| `web.json(status, value)` | `application/json` (a `Json` value, serialized) |
| `web.respond(status, body, contentType)` | anything |

```x
route create(req: Request) -> Response on post "/users" {
    let u = web.bodyJson(req)
    return web.json(201, u)
}
```

Unmatched requests get a `404 Not Found`.

## Running

```x
async entry main(args: String[]) -> Integer {
    web.serve(8080)        // blocking HTTP/1.1 server
    return 0
}
module App {}              // default DI wiring
```

```console
$ xc app.xi && ./build/app
web: serving on http://0.0.0.0:8080
```

## Notes & limits

- HTTP/1.1, blocking, one request per connection (no keep-alive) — fine for an
  API behind a reverse proxy; concurrency and keep-alive are future work.
- **HTTPS / HTTP-2 / HTTP-3** are planned; they need a TLS/QUIC dependency — see
  the [web-stack proposal](proposals/web-stack.md). Today `web.serve` is plaintext
  HTTP, so put it behind a TLS-terminating proxy for production.
- No `%`-decoding of query values yet; no multipart parsing.

See `examples/web_demo.xi`.
