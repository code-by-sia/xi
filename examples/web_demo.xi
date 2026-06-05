// std/web — a REST API in a few lines. Implement WebRequestHandler and route by
// overloading `handle` with `where` guards on the request. Replies use
// res.send(dto) (auto-serialized to JSON) — no manual JSON. web.serve runs a
// blocking HTTP/1.1 server.
//
//   xc examples/web_demo.xi && ./build/web_demo
//   curl localhost:8080/health
//   curl 'localhost:8080/user?name=Ada'
//   curl -X POST -d '{"msg":"hello"}' localhost:8080/echo
import "std/web.xi"

event Health { ok: Bool, service: String }
event User   { name: String, active: Bool }
type  Echo = { msg: String }

interface Repo { mapper active(name: String) -> Bool }
class Names implements Repo {
    deps {}
    mapper active(name: String) -> Bool { return name == "Ada" }
}

class Api implements WebRequestHandler {
    deps { repo: Repo }                                  // injected like any service

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/health" {
        res.send(Health { ok: true, service: "demo" })
    }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/user" {
        let name = req.query("name")                     // ?name=...
        res.send(User { name: name, active: repo.active(name) })
    }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/echo" {
        res.send(req.parse(Echo))                        // typed body round-trip
    }
    action handle(req: HttpRequest, res: HttpResponse) {
        res.sendStatus(404, "Not Found")                 // default overload
    }
}

module App { bind WebRequestHandler -> Api }

async entry main(args: String[]) -> Integer {
    web.serve(8080)
    return 0
}
