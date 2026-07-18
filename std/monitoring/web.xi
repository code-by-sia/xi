// std/monitoring/web — monitoring for the built-in HTTP server.
//
// One of the two modules that knows about both monitoring and web, which is what
// keeps those independent: std/monitoring never mentions HTTP, and std/web never
// mentions monitoring. Import this when your app serves HTTP:
//
//     import "std/monitoring/web.xi"
//
//     entry (mon: Monitoring) main(args: String[]) -> Integer {
//         mon.startMonitor()
//         web.serve(8080)
//         return 0
//     }
//
// `WebMonitoring` reports the server's numbers under "web". It implements
// MonitorableResource like anything else — nothing about it is special-cased.
//
// `MonitorController` is optional: import this module and the endpoints below
// mount themselves (controllers auto-register). If you would rather expose your
// own shape — different paths, auth, a subset — leave it out and inject
// `Monitoring` into a controller of your own; `mon.health()` and `mon.report()`
// give you the same Json.
import "std/monitoring.xi"
import "std/web.xi"
import "std/json.xi"

// The server's own numbers, reported under "web".
class WebMonitoring implements MonitorableResource {
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

// Ready-made endpoints:
//
//     GET /monitor/health    {"status":"UP","checks":{…}}  (503 when DOWN)
//     GET /monitor/info      module id / name / version
//     GET /monitor/memory    rss, peak, uptime
//     GET /monitor/metrics   the above plus every resource
//
// Your own controllers keep working alongside it; each request goes to the one
// whose `where` guard matches.
class MonitorController implements WebRequestHandler {
    // `as singleton` marks Monitoring singleton for the whole program, so the
    // registry `main` calls startMonitor() on is the same one reporting here —
    // otherwise each injection site would get its own, unstarted, copy.
    deps { mon: Monitoring as singleton }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/health" {
        let body = json.stringify(mon.health())
        if mon.healthy() {
            res.sendText(200, body)
        } else {
            res.sendText(503, body)
        }
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/metrics" {
        res.sendText(200, json.stringify(mon.report()))
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/memory" {
        let o = json.object()
        o = json.set(o, "rssBytes", json.int(monitor.rss()))
        o = json.set(o, "peakRssBytes", json.int(monitor.peakRss()))
        o = json.set(o, "uptimeMs", json.int(monitor.uptimeMs()))
        res.sendText(200, json.stringify(o))
    }

    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/monitor/info" {
        let o = json.object()
        o = json.set(o, "id", json.str(monitor.info(0)))
        o = json.set(o, "name", json.str(monitor.info(1)))
        o = json.set(o, "version", json.str(monitor.info(2)))
        res.sendText(200, json.stringify(o))
    }
}
