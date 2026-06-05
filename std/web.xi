// std/web — a tiny REST framework over HTTP/1.1.  import "std/web.xi"
//
// Declare handlers with the `route` function kind inside a class (DI-wired, like
// any service); they are auto-discovered and matched by method + path:
//
//     class Users {
//         deps { repo: Repo }
//         route show(req: Request) -> Response on get "/users/:id" {
//             return web.json(200, userToJson(repo.find(web.param(req, "id"))))
//         }
//     }
//     async entry main(args: String[]) -> Integer { web.serve(8080) return 0 }
//     module App {}
//
// `web.serve` runs a blocking HTTP/1.1 server. (HTTPS / HTTP-2-3 are planned —
// see the web-stack proposal.)
namespace web

// Note: we call the JSON runtime helpers directly (not the `json` namespace) so
// that this module can offer a `web.json(...)` response builder without the
// namespace prefixer clobbering `json.*` references.
extern "C" {
    mapper   xstd_req_method(r: Request) -> String
    mapper   xstd_req_path(r: Request) -> String
    mapper   xstd_req_param(r: Request, name: String) -> String
    mapper   xstd_req_query(r: Request, name: String) -> String
    mapper   xstd_req_header(r: Request, name: String) -> String
    mapper   xstd_req_body(r: Request) -> String
    mapper   xstd_resp(status: Integer, body: String, ctype: String) -> Response
    producer xstd_web_serve(port: Integer)
    mapper   xstd_json_stringify(v: Json) -> String
    producer xstd_json_parse(s: String) -> Json
}

// ── Request accessors ───────────────────────────────────────────────
mapper method(r: Request) -> String               { return xstd_req_method(r) }
mapper path(r: Request) -> String                  { return xstd_req_path(r) }
mapper param(r: Request, name: String) -> String   { return xstd_req_param(r, name) }   // :id segments
mapper query(r: Request, name: String) -> String   { return xstd_req_query(r, name) }   // ?k=v
mapper header(r: Request, name: String) -> String  { return xstd_req_header(r, name) }
mapper body(r: Request) -> String                  { return xstd_req_body(r) }
mapper bodyJson(r: Request) -> Json                { return xstd_json_parse(xstd_req_body(r)) }

// ── Response builders ───────────────────────────────────────────────
mapper respond(status: Integer, body: String, ctype: String) -> Response {
    return xstd_resp(status, body, ctype)
}
mapper text(status: Integer, body: String) -> Response {
    return xstd_resp(status, body, "text/plain; charset=utf-8")
}
mapper json(status: Integer, payload: Json) -> Response {
    return xstd_resp(status, xstd_json_stringify(payload), "application/json")
}

// ── Server ──────────────────────────────────────────────────────────
producer serve(port: Integer) { xstd_web_serve(port) }
