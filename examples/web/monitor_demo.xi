// Monitoring a service. Each subsystem contributes through the
// MonitorableResource interface, so std/monitoring never has to know that HTTP
// or a database exists — you import the bridge for what you actually use.
//
//   xc examples/web/monitor_demo.xi && ./build/monitor-demo
//   curl localhost:4080/monitor/health
//   curl localhost:4080/monitor/metrics
import "std/monitoring/web.xi"        // WebMonitoring + the /monitor/* endpoints
import "std/monitoring/database.xi"   // DatabaseMonitoring (probes the provider)
import "std/monitoring/thread.xi"     // ThreadMonitoring (spawned / live)
import "std/query.xi"
import "std/web.xi"

// Your own controller sits alongside the monitor endpoints; each request goes
// to whichever handler's `where` guard matches.
class Api implements WebRequestHandler {
    deps {}
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/hello" {
        res.sendText(200, "hello")
    }
}

// Anything can be a resource — implement the same interface the bundled ones do.
class CacheMonitoring implements MonitorableResource {
    deps {}
    state { started: Bool = false }
    mapper    name() -> String => "cache"
    consumer  startMonitor() { this.started = true }
    producer  healthy() -> Bool => this.started
    producer  metrics() -> Json {
        let o = json.object()
        o = json.set(o, "entries", json.int(42))
        return o
    }
}

module App {
    id = "monitor-demo"
    name = "Monitor Demo"
    version = "1.0.0"
    bind QueryProvider -> MemorySource as singleton

    // Monitoring is opt-in: nothing runs until `startMonitor()` is called.
    entry (mon: Monitoring as singleton) main(args: String[]) -> Integer {
        mon.startMonitor()
        monitor.gauge("workers", 4)      // report a number the app already knows
        web.serve(4080)
        return 0
    }
}
