// std/monitor — process health, memory and metrics for a running app.
//
// Read the numbers directly:
//
//     import "std/monitor.xi"
//     monitor.rss()          // resident bytes right now
//     monitor.peakRss()      // high-water mark
//     monitor.uptimeMs()     // since start
//     monitor.requests()     // requests the built-in server has served
//
// In a web app the endpoints mount themselves: MonitorController is a
// WebRequestHandler and controllers auto-register, so importing is enough — no
// bind, no handler code of your own.
//
//     import "std/monitor.xi"
//
//     GET /monitor/health    {"status":"UP"} (503 + "DOWN" if a check fails)
//     GET /monitor/info      module id / name / version
//     GET /monitor/memory    rss, peak, uptime
//     GET /monitor/metrics   the above plus the request count
//
// Your own controllers keep working alongside it — every WebRequestHandler is
// registered, and each request goes to the one whose `where` guard matches.
//
// A `HealthCheck` reports one dependency (a database, a queue). Implement it and
// every implementor is collected into /monitor/health automatically:
//
//     class DbCheck implements HealthCheck {
//         deps { db: QueryProvider }
//         mapper    name() -> String => "database"
//         predicate healthy() -> Bool => db.ping()
//     }
//
// Kept un-namespaced (like std/data) so `implements HealthCheck` reads bare; the
// readings live under `monitor.` in std/monitor_metrics.xi.
import "std/monitor_metrics.xi"
import "std/json.xi"
import "std/web.xi"

// One dependency's health. Every implementor is folded into /monitor/health;
// `name` labels it in the response.
interface HealthCheck {
    mapper    name() -> String
    predicate healthy() -> Bool
}

mapper healthWord(ok: Bool) -> String {
    if ok { return "UP" }
    return "DOWN"
}

// The /monitor/* endpoints. Registered automatically as a controller.
class MonitorController implements WebRequestHandler {
    deps { checks: HealthCheck[] }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/health" {
        let o = json.object()
        let up = true
        let items = json.object()
        for c in checks {
            let ok = c.healthy()
            if not ok { up = false }
            items = json.set(items, c.name(), json.str(healthWord(ok)))
        }
        o = json.set(o, "status", json.str(healthWord(up)))
        if checks.len > 0 { o = json.set(o, "checks", items) }
        if up {
            res.sendText(200, json.stringify(o))
        } else {
            res.sendText(503, json.stringify(o))
        }
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/memory" {
        let o = json.object()
        o = json.set(o, "rssBytes", json.int(monitor.rss()))
        o = json.set(o, "peakRssBytes", json.int(monitor.peakRss()))
        o = json.set(o, "uptimeMs", json.int(monitor.uptimeMs()))
        res.sendText(200, json.stringify(o))
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/metrics" {
        res.sendText(200, json.stringify(monitor.snapshot()))
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/info" {
        let o = json.object()
        o = json.set(o, "id", json.str(monitor.info(0)))
        o = json.set(o, "name", json.str(monitor.info(1)))
        o = json.set(o, "version", json.str(monitor.info(2)))
        res.sendText(200, json.stringify(o))
    }
}
