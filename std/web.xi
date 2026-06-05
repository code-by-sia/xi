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
// `web.serve` runs a blocking HTTP/1.1 server. (HTTPS / HTTP-2-3 are planned —
// see the web-stack proposal.)
namespace web

import "web_core.xi"

extern "C" {
    producer xstd_web_serve(port: Integer)
    producer xstd_web_serve_tls(port: Integer, cert: String, key: String)
}

// ── Server ──────────────────────────────────────────────────────────
producer serve(port: Integer) { xstd_web_serve(port) }

// HTTPS. Requires the toolchain to be built with TLS: compile with `XC_TLS=1`
// (needs OpenSSL). Without it, this prints a notice and serves nothing.
producer serveTLS(port: Integer, cert: String, key: String) {
    xstd_web_serve_tls(port, cert, key)
}
