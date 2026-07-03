// Extracting path, body, and headers separately as typed DTOs.
//
// `web.route(req, method, pattern)` routes (and captures :params); then each
// source is its own flat Json — `web.params` / `web.query` / `web.headers` /
// `web.body` — decoded into a small type with the general `as T` (which coerces
// string scalars, so a "44" path segment becomes an Integer).
//
//   xc examples/web_params_demo.xi && ./build/web_params_demo   # serves until Ctrl-C
import "std/log.xi"
import "std/web.xi"

type IdRef   = { id: Integer }
type NewUser = { name: String, email: String }
type Auth    = { authorization: String }

event UserView { id: Integer, name: String }

class UserApi implements WebRequestHandler {
    deps { logger: Logger }

    // POST /users/:id   { "name": ..., "email": ... }   Authorization: ...
    action handle(req: HttpRequest, res: HttpResponse) where web.route(req, "POST", "/users/:id") {
        let ref  = web.params(req)  as IdRef       // path   -> { id: Integer }
        let body = web.body(req)    as NewUser     // body   -> { name, email }
        let auth = web.headers(req) as Auth        // header -> { authorization }
        logger.info("create id=" + ref.id + " by " + auth.authorization)
        res.send(UserView { id: ref.id, name: body.name })
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
