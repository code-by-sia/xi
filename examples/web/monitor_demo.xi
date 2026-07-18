// Actuator-style monitoring: import std/monitor and the endpoints mount
// themselves — MonitorController is a WebRequestHandler, and controllers
// auto-register, so there is no bind and no handler code to write.
//
//   xc examples/web/monitor_demo.xi && ./build/monitor-demo
//   curl localhost:4080/monitor/health
//   curl localhost:4080/monitor/metrics
import "std/monitor.xi"
import "std/web.xi"

// Your own controller sits alongside the monitor endpoints; each request goes
// to whichever handler's `where` guard matches.
class Api implements WebRequestHandler {
    deps {}
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/hello" {
        res.sendText(200, "hello")
    }
}

// Any HealthCheck implementor is folded into /monitor/health automatically.
// Return false here and health reports DOWN with a 503.
class DiskCheck implements HealthCheck {
    deps {}
    mapper    name() -> String => "disk"
    predicate healthy() -> Bool => true
}

module App {
    id = "monitor-demo"
    name = "Monitor Demo"
    version = "1.0.0"

    entry main(args: String[]) -> Integer {
        web.serve(4080)
        return 0
    }
}
