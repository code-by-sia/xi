// std/monitoring/memory — resident memory as a Monitoring implementation.
//
// Memory is not privileged: it contributes through the same interface as web or
// a database, so a program that does not import this reports no memory at all.
//
//     import "std/monitoring/memory.xi"
//
// Reports `rssBytes` and `peakRssBytes` under "memory". Health is `true` unless
// you set `maxRssBytes`, which is useful to catch a process that has grown past
// what the deployment allows.
import "std/monitoring.xi"
import "std/json.xi"

class MemoryMonitoring implements Monitoring {
    deps {}
    // 0 = no ceiling: report the numbers, never claim unhealthy.
    state { maxRssBytes: Integer = 0, startRss: Integer = 0 }

    mapper name() -> String => "memory"

    // Record the baseline, so `growthBytes` means growth since monitoring began
    // rather than since some arbitrary earlier point.
    consumer startMonitor() { this.startRss = monitor.rss() }

    producer healthy() -> Bool {
        if this.maxRssBytes <= 0 { return true }
        return monitor.rss() <= this.maxRssBytes
    }

    producer metrics() -> Json {
        let o = json.object()
        o = json.set(o, "rssBytes", json.int(monitor.rss()))
        o = json.set(o, "peakRssBytes", json.int(monitor.peakRss()))
        o = json.set(o, "growthBytes", json.int(monitor.rss() - this.startRss))
        return o
    }
}
