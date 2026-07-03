// Regression demo for web.route with multiple path params AND a trailing literal
// segment (e.g. `/playlists/:playlistId/tracks/:trackId/move`). Exercised by
// scripts/web_route_test.sh (which compiles this, starts it, and curls the
// routes). Compiled in CI; not run there directly (web.serve blocks).
import "std/web.xi"
import "std/log.xi"

event Ok          { ok: Bool }
type  IdRef       = { id: Integer }
event User        { id: Integer }
type  Move        = { playlistId: Integer, trackId: Integer }
event MoveResult  { playlistId: Integer, trackId: Integer }

class Routes implements WebRequestHandler {
    deps { logger: Logger }

    action handle(req: HttpRequest, res: HttpResponse) where web.route(req, "GET", "/health") {
        res.send(Ok { ok: true })
    }
    action handle(req: HttpRequest, res: HttpResponse) where web.route(req, "GET", "/users/:id") {
        let r = web.params(req) as IdRef
        res.send(User { id: r.id })
    }
    // two params with a trailing literal segment ("move")
    action handle(req: HttpRequest, res: HttpResponse) where web.route(req, "POST", "/playlists/:playlistId/tracks/:trackId/move") {
        let m = web.params(req) as Move
        res.send(MoveResult { playlistId: m.playlistId, trackId: m.trackId })
    }
    action handle(req: HttpRequest, res: HttpResponse) {
        res.sendStatus(404, "Not Found")
    }
}

module App { bind WebRequestHandler -> Routes }

async entry main(args: String[]) -> Integer {
    web.serve(8137)
    return 0
}
