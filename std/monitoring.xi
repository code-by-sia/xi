// std/monitoring — a mechanism for monitoring a running process.
//
// This module knows nothing about HTTP, databases, threads or the OS. It defines
// what a monitor looks like and loops over whatever implements it:
//
//     Monitoring           one subsystem that can be watched
//     MonitoringRegistry   every Monitoring in the program, assembled
//
// A subsystem adds monitoring by implementing `Monitoring` — never by this
// module knowing the subsystem exists. Import the ones you want; each is a
// separate module beside its subsystem:
//
//     import "std/monitoring/memory.xi"     // MemoryMonitoring
//     import "std/monitoring/cpu.xi"        // CpuMonitoring
//     import "std/monitoring/web.xi"        // WebMonitoring   + endpoints
//     import "std/monitoring/query.xi"   // QueryMonitoring
//     import "std/monitoring/thread.xi"     // ThreadMonitoring
//
// Nothing is active until you switch it on. Monitoring is **off by default** —
// importing a module makes it available, not running. Enable it in `main`:
//
//     entry (mon: MonitoringRegistry as singleton) main(args: String[]) -> Integer {
//         mon.enable()                  // starts every imported monitor
//         web.serve(8080)
//         return 0
//     }
//
// Until `enable()` is called the registry reports nothing and the HTTP endpoints
// in std/monitoring/web.xi answer 404, so an app that never enables monitoring
// carries no monitoring surface at all.
import "std/monitoring/metrics.xi"
import "std/json.xi"

// One subsystem that can be watched. Implement it for a server, a pool, a queue,
// a cache — anything with a health answer or numbers worth reporting.
//
//   name()          labels it in the reports
//   startMonitor()  called once, when monitoring is enabled; do nothing if there
//                   is nothing to set up
//   healthy()       usable right now? (a producer: probing is allowed)
//   metrics()       its numbers, as a Json object
interface Monitoring {
    mapper    name() -> String
    consumer  startMonitor()
    producer  healthy() -> Bool
    producer  metrics() -> Json
}

// Every Monitoring in the program, assembled. Inject it to enable monitoring and
// to read the results.
interface MonitoringRegistry {
    consumer  enable()             // start every monitor; call once, from main
    predicate isEnabled() -> Bool  // false until enable() is called
    producer  report() -> Json     // uptime + gauges + every monitor's metrics
    producer  health() -> Json     // {"status": …, "checks": {…}}
    producer  healthy() -> Bool    // false if any monitor or reported status is down
}

mapper healthWord(ok: Bool) -> String {
    if ok { return "UP" }
    return "DOWN"
}

// Collects every Monitoring implementor — no registration call and no bind — and
// loops over them to build each report. Stays inert until `enable()`.
class MonitorRegistry implements MonitoringRegistry {
    deps { monitors: Monitoring[] }
    state { on: Bool = false }

    consumer enable() {
        this.on = true
        for m in monitors { m.startMonitor() }
    }

    predicate isEnabled() -> Bool => this.on

    producer report() -> Json {
        if not this.on { return json.object() }
        let o = monitor.snapshot()                    // uptime + reported gauges
        for m in monitors { o = json.set(o, m.name(), m.metrics()) }
        return o
    }

    producer healthy() -> Bool {
        if not this.on { return true }                // nothing claimed while off
        for m in monitors { if not m.healthy() { return false } }
        let i = 0
        while i < monitor.statusCount() {
            if not monitor.statusUp(i) { return false }
            i = i + 1
        }
        return true
    }

    producer health() -> Json {
        let o = json.object()
        if not this.on {
            o = json.set(o, "status", json.str("DISABLED"))
            return o
        }
        let items = json.object()
        let n = 0
        for m in monitors {
            items = json.set(items, m.name(), json.str(healthWord(m.healthy())))
            n = n + 1
        }
        let i = 0
        while i < monitor.statusCount() {
            items = json.set(items, monitor.statusName(i), json.str(healthWord(monitor.statusUp(i))))
            n = n + 1
            i = i + 1
        }
        o = json.set(o, "status", json.str(healthWord(healthy())))
        if n > 0 { o = json.set(o, "checks", items) }
        return o
    }
}
