// std/monitoring/web — monitoring for the built-in HTTP server.
//
// One of the modules that knows about both monitoring and web, which is what
// keeps those independent: std/monitoring never mentions HTTP, and std/web never
// mentions monitoring.
//
//     import "std/monitoring/web.xi"
//
//     entry (mon: MonitoringRegistry as singleton) main(args: String[]) -> Integer {
//         mon.enable()                 // nothing below is live until this runs
//         web.serve(8080)
//         return 0
//     }
//
// `WebMonitoring` reports the server's numbers under "web". It implements
// `Monitoring` like anything else — nothing about it is special-cased.
//
// `MonitorController` exposes the reports over HTTP. Importing this module makes
// the endpoints *available*, not *on*: until `enable()` is called they answer
// 404, so an app that never enables monitoring exposes no monitoring surface.
//
// Want a different shape — other paths, auth, a subset? Leave the controller be
// and inject `MonitoringRegistry` into a controller of your own; `health()` and
// `report()` hand you the same Json.
import "std/monitoring.xi"
import "std/web.xi"
import "std/json.xi"

// The server's own numbers, reported under "web".
class WebMonitoring implements Monitoring {
    deps {}
    mapper    name() -> String => "web"
    consumer  startMonitor() { }              // the counter runs with the server
    producer  healthy() -> Bool => true
    producer  metrics() -> Json {
        let o = json.object()
        o = json.set(o, "requests", json.int(web.requestCount()))
        return o
    }
}

// Endpoints, live only while monitoring is enabled:
//
//     GET /monitor/health    {"status":"UP","checks":{…}}  (503 when DOWN)
//     GET /monitor/info      module id / name / version
//     GET /monitor/metrics   uptime, gauges, and every monitor
//
// Your own controllers keep working alongside these; each request goes to the
// one whose `where` guard matches.
class MonitorController implements WebRequestHandler {
    // `as singleton` marks the registry singleton for the whole program, so the
    // one `main` enables is the one answering here — otherwise each injection
    // site would get its own, still-disabled copy.
    deps { mon: MonitoringRegistry as singleton }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/health" {
        if not mon.isEnabled() {
            res.sendText(404, "Not Found")
        } else {
            let body = json.stringify(mon.health())
            if mon.healthy() {
                res.sendText(200, body)
            } else {
                res.sendText(503, body)
            }
        }
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/metrics" {
        if not mon.isEnabled() {
            res.sendText(404, "Not Found")
        } else {
            res.sendText(200, json.stringify(mon.report()))
        }
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/info" {
        if not mon.isEnabled() {
            res.sendText(404, "Not Found")
        } else {
            let o = json.object()
            o = json.set(o, "id", json.str(monitor.info(0)))
            o = json.set(o, "name", json.str(monitor.info(1)))
            o = json.set(o, "version", json.str(monitor.info(2)))
            res.sendText(200, json.stringify(o))
        }
    }
}
