// std/web — a REST API in a few lines. Every class implementing
// WebRequestHandler is a controller and is auto-registered (DI-wired) — no
// `bind` needed. Controllers are tried in order; the first handle overload whose
// `where` guard matches wins. Replies use res.send(dto) (auto-serialized to
// JSON) — no manual JSON. web.serve runs a blocking HTTP/1.1 server.
//
//   xc examples/web_demo.xi && ./build/web_demo
//   curl localhost:8080/health
//   curl 'localhost:8080/user?name=John Doe'
//   curl -X POST -d '{"msg":"hello"}' localhost:8080/echo
import "std/web.xi"

event Health { ok: Bool, service: String }
event User   { name: String, active: Bool }
type  Echo = { msg: String }

interface Repo { mapper active(name: String) -> Bool }
class Names implements Repo {
    deps {}
    mapper active(name: String) -> Bool { return name == "John Doe" }
}

// A controller per concern — no registration, just implement WebRequestHandler.
class HealthController implements WebRequestHandler {
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/health" {
        res.send(Health { ok: true, service: "demo" })
    }
}

class UserController implements WebRequestHandler {
    deps { repo: Repo }                                  // injected like any service

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/user" {
        let name = req.query("name")                     // ?name=...
        res.send(User { name: name, active: repo.active(name) })
    }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/echo" {
        res.send(req.parse(Echo))                        // typed body round-trip
    }
}

module App {}                                            // no bind — auto-registered

async entry main(args: String[]) -> Integer {
    runWithDelay(30000) { web.shutdown() }   // self-terminate after 30s so the server never blocks
    web.serve(8080)
    return 0
}
