// std/monitoring — a mechanism for monitoring a running process.
//
// This module knows nothing about HTTP, databases or threads. It defines what a
// monitorable thing looks like, and collects whatever implements it:
//
//     MonitorableResource   one thing that can be watched (a server, a pool)
//     Monitoring            the assembled health and metrics reports
//
// A subsystem adds monitoring by implementing `MonitorableResource` — never by
// this module knowing the subsystem exists. The ones that ship with the library
// live beside their subsystem, and you enable only what you use:
//
//     import "std/monitoring/web.xi"        // WebMonitoring
//     import "std/monitoring/database.xi"   // DatabaseMonitoring
//     import "std/monitoring/thread.xi"     // ThreadMonitoring
//
// Monitoring is **opt-in**: nothing starts until you ask it to, in `main`.
//
//     entry (mon: Monitoring) main(args: String[]) -> Integer {
//         mon.startMonitor()            // start every imported resource
//         web.serve(8080)
//         return 0
//     }
//
// Then read the reports wherever you need them — inject `Monitoring` into a
// controller of your own to expose them over HTTP, or log them from a job.
// std/monitoring/web.xi ships a ready-made health controller if you want one.
import "std/monitoring/metrics.xi"
import "std/json.xi"

// One thing that can be watched. Implement it for a subsystem — a connection
// pool, a queue, a cache — and it joins the reports automatically.
//
//   name()          labels this resource in the reports
//   startMonitor()  begin monitoring (open a handle, reset counters); called
//                   once, from Monitoring.startMonitor(). Do nothing if there
//                   is nothing to set up.
//   healthy()       is it usable right now? (a producer: probing is allowed)
//   metrics()       its numbers, as a Json object
interface MonitorableResource {
    mapper    name() -> String
    consumer  startMonitor()
    producer  healthy() -> Bool
    producer  metrics() -> Json
}

// The assembled reports. Inject it in `main` to start monitoring, and anywhere
// else you want to read the results.
interface Monitoring {
    consumer  startMonitor()       // start every resource; call once, from main
    producer  report() -> Json     // process readings + gauges + every resource
    producer  health() -> Json     // {"status": …, "checks": {…}}
    producer  healthy() -> Bool    // false if any resource or reported status is down
}

mapper healthWord(ok: Bool) -> String {
    if ok { return "UP" }
    return "DOWN"
}

// Collects every MonitorableResource in the program — no registration call and
// no bind: implementors are found and injected.
class Monitor implements Monitoring {
    deps { resources: MonitorableResource[] }

    consumer startMonitor() {
        for r in resources { r.startMonitor() }
    }

    producer report() -> Json {
        let o = monitor.snapshot()              // process readings + reported gauges
        for r in resources { o = json.set(o, r.name(), r.metrics()) }
        return o
    }

    producer healthy() -> Bool {
        for r in resources { if not r.healthy() { return false } }
        let i = 0
        while i < monitor.statusCount() {
            if not monitor.statusUp(i) { return false }
            i = i + 1
        }
        return true
    }

    producer health() -> Json {
        let items = json.object()
        let n = 0
        for r in resources {
            items = json.set(items, r.name(), json.str(healthWord(r.healthy())))
            n = n + 1
        }
        let i = 0
        while i < monitor.statusCount() {
            items = json.set(items, monitor.statusName(i), json.str(healthWord(monitor.statusUp(i))))
            n = n + 1
            i = i + 1
        }
        let o = json.object()
        o = json.set(o, "status", json.str(healthWord(healthy())))
        if n > 0 { o = json.set(o, "checks", items) }
        return o
    }
}
