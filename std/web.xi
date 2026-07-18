// std/web — a tiny REST framework over HTTP/1.1.  import "std/web.xi"
//
// Implement `WebRequestHandler` and route with `where`-overloaded `handle`
// methods. The framework hands each request a *mutable* response; reply with
// `res.send(dto)` (auto-serialized via the bound WebTransport) or
// `res.sendStatus(code, msg)`. There is no manual JSON:
//
//     event Health { ok: Bool }
//
//     class Api implements WebRequestHandler {
//         action handle(req: HttpRequest, res: HttpResponse) where req.path == "/health" {
//             res.send(Health { ok: true })
//         }
//         action handle(req: HttpRequest, res: HttpResponse) {
//             res.sendStatus(404, "Not Found")
//         }
//     }
//     module App { bind WebRequestHandler -> Api }
//     async entry main(args: String[]) -> Integer { web.serve(8080) return 0 }
//
// Request:  req.path, req.method, req.body, req.param(n), req.query(n),
//           req.header(n), req.parse(T) (typed body via WebTransport).
// Response: res.send(dto), res.sendStatus(code, msg), res.sendText(code, body).
//
// `web.serve` runs a blocking HTTP/1.1 server; `web.serveTLS` (XC_TLS=1) and
// `web.serveHttp2` (XC_HTTP2=1) add HTTPS / HTTP-2. HTTP/3 (QUIC) is the one
// remaining transport.
namespace web

import "web_core.xi"

extern "C" {
    producer xstd_web_serve(port: Integer)
    mapper   xstd_request_count() -> Integer
    producer xstd_web_serve_tls(port: Integer, cert: String, key: String)
    producer xstd_web_serve_http2(port: Integer, cert: String, key: String)
    producer xstd_web_shutdown()
    mapper   xstd_web_match(req: HttpRequest, method: String, pattern: String) -> Bool
    mapper   xstd_req_params_json(req: HttpRequest) -> Json
    mapper   xstd_req_query_json(req: HttpRequest) -> Json
    mapper   xstd_req_headers_json(req: HttpRequest) -> Json
    mapper   xstd_req_body(req: HttpRequest) -> String
    producer xstd_json_parse(s: String) -> Json
}

// ── Routing + per-source extraction ──────────────────────────────────
// Route on method + a `/users/:id` pattern; captures the path params for
// `web.params`. Use as a `where` guard, then decode each source with `as T`:
//
//   action handle(req, res) where web.route(req, "POST", "/users/:id") {
//       let id   = web.params(req)  as IdRef
//       let body = web.body(req)    as NewUser
//       res.send(create(id.id, body.name))
//   }
predicate route(req: HttpRequest, method: String, pattern: String) {
    return xstd_web_match(req, method, pattern)
}
// Each source as a flat Json (decode with `as T`). path/query/header values are
// strings; `as T` coerces them ("42" -> Integer, "true" -> Bool). Header names
// are normalized (Content-Type -> content_type).
producer params(req: HttpRequest) -> Json  { return xstd_req_params_json(req) }
producer query(req: HttpRequest) -> Json   { return xstd_req_query_json(req) }
producer headers(req: HttpRequest) -> Json { return xstd_req_headers_json(req) }
producer body(req: HttpRequest) -> Json    { return xstd_json_parse(xstd_req_body(req)) }

// ── Server ──────────────────────────────────────────────────────────
producer serve(port: Integer) { xstd_web_serve(port) }

// Requests this server has served. Exposed here because the count is the web
// layer's own number; std/monitoring/web.xi reports it as a MonitorableResource,
// so monitoring never has to know that HTTP exists.
mapper requestCount() -> Integer => xstd_request_count()

// Stop a running server: unblocks `serve` so it returns. Safe to call from
// another thread — e.g. `runWithDelay(30000) { web.shutdown() }` before `serve`
// gives a self-terminating server (used by the examples so CI never blocks).
producer shutdown() { xstd_web_shutdown() }

// HTTPS. Requires the toolchain to be built with TLS: compile with `XC_TLS=1`
// (needs OpenSSL). Without it, this prints a notice and serves nothing.
producer serveTLS(port: Integer, cert: String, key: String) {
    xstd_web_serve_tls(port, cert, key)
}

// HTTP/2 over TLS (ALPN `h2`, falling back to HTTP/1.1). Build with `XC_HTTP2=1`
// (needs OpenSSL + nghttp2). Same handler stack as plaintext.
producer serveHttp2(port: Integer, cert: String, key: String) {
    xstd_web_serve_http2(port, cert, key)
}
