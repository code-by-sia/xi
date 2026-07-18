// Monitoring a service. Each subsystem implements the same `Monitoring`
// interface and the registry loops over them, so std/monitoring never has to
// know that HTTP or a query provider exists — you import what you use.
//
// Monitoring is off until `enable()` runs; pass any argument to switch it on and
// watch the endpoints go from 404 to live.
//
//   xc examples/web/monitor_demo.xi
//   ./build/monitor-demo            # monitoring off  -> /monitor/* is 404
//   ./build/monitor-demo --monitor  # monitoring on   -> reports
import "std/monitoring/memory.xi"
import "std/monitoring/cpu.xi"
import "std/monitoring/web.xi"
import "std/monitoring/query.xi"
import "std/monitoring/thread.xi"
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

// Anything can be a monitor — implement the same interface the bundled ones do.
class CacheMonitoring implements Monitoring {
    deps {}
    state { started: Bool = false }
    mapper    name() -> String => "cache"
    consumer  startMonitor() { this.started = true }
    producer  healthy() -> Bool => this.started
    producer  metrics() -> Json {
        let o = json.object()
        return json.set(o, "entries", json.int(42))
    }
}

module App {
    id = "monitor-demo"
    name = "Monitor Demo"
    version = "1.0.0"
    bind QueryProvider -> MemorySource as singleton

    entry (mon: MonitoringRegistry as singleton) main(args: String[]) -> Integer {
        if args.len >= 2 { mon.enable() }     // off unless asked
        monitor.gauge("workers", 4)           // a number the app already knows
        web.serve(4080)
        return 0
    }
}
