// std/web — a REST API in a few lines. Handlers are `route` methods (DI-wired,
// auto-discovered); web.serve runs a blocking HTTP/1.1 server.
//
//   xc examples/web_demo.xi && ./build/web_demo
//   curl localhost:8080/health
//   curl 'localhost:8080/users/1?greet=hi'
//   curl -X POST -d '{"msg":"hello"}' localhost:8080/echo
import "std/web.xi"
import "std/json.xi"

interface Repo { mapper name(id: String) -> String }
class Names implements Repo {
    deps {}
    mapper name(id: String) -> String {
        if id == "1" { return "Ada" }
        if id == "2" { return "Grace" }
        return "unknown"
    }
}

class Api {
    deps { repo: Repo }                                   // injected like any service

    route health(req: Request) -> Response on get "/health" {
        return web.text(200, "ok")
    }
    route user(req: Request) -> Response on get "/users/:id" {
        let o = json.object()
        o = json.set(o, "id",    json.str(web.param(req, "id")))      // :id path param
        o = json.set(o, "name",  json.str(repo.name(web.param(req, "id"))))
        o = json.set(o, "greet", json.str(web.query(req, "greet")))   // ?greet=...
        return web.json(200, o)
    }
    route echo(req: Request) -> Response on post "/echo" {
        return web.json(200, web.bodyJson(req))                       // echo the JSON body
    }
}

async entry main(args: String[]) -> Integer {
    web.serve(8080)
    return 0
}
module App {}
