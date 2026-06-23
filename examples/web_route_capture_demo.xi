// Routing + capture together: route in the `where` guard, then use `capture` in
// the body to name a looked-up value (bound from inside a call) and reuse it.
//
//   xc examples/web_route_capture_demo.xi && ./build/web_route_capture_demo
//
// Try it:
//   curl -s localhost:8080/users/1      ->  {"id":1,"name":"Ada"}
//   curl -s localhost:8080/users/2      ->  404 (inactive/missing)
import "std/log.xi"
import "std/web.xi"

type UserId = { id: Integer }
type User   = { id: Integer, name: String, active: Bool }
event UserView { id: Integer, name: String }

// a tiny demo "store"
mapper    findUser(id: Integer) -> User {
    if id == 1 { return User { id: 1, name: "Ada", active: true } }
    return User { id: id, name: "", active: false }
}
predicate isActive(u: User) { return u.active }

class UserApi implements WebRequestHandler {
    deps { logger: Logger }

    // route on method + path; the body parses the path param and captures the
    // looked-up user from inside the condition, reusing it in the response.
    action handle(req: HttpRequest, res: HttpResponse) where web.route(req, "GET", "/users/:id") {
        let ref = web.params(req) as UserId
        if isActive(findUser(ref.id) capture u: User) {
            logger.info("serving user " + u.id + " (" + u.name + ")")
            res.send(UserView { id: u.id, name: u.name })
        } else {
            res.sendStatus(404, "no active user " + ref.id)
        }
    }

    action handle(req: HttpRequest, res: HttpResponse) {
        res.sendStatus(404, "Not Found")
    }
}

module App { bind WebRequestHandler -> UserApi }

async entry main(args: String[]) -> Integer {
    web.serve(8080)
    return 0
}
