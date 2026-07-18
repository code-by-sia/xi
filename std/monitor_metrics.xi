// std/monitor_metrics — the `monitor.*` readings behind std/monitor.
//
// Split out because these live under a namespace (`monitor.rss()`), while the
// HealthCheck interface and the controller in std/monitor.xi must keep bare
// names so user code can `implements HealthCheck` without a prefix. Import
// std/monitor.xi — it pulls this in.
import "std/json.xi"

namespace monitor

extern "C" {
    mapper xstd_mem_rss() -> Integer
    mapper xstd_mem_peak() -> Integer
    mapper xstd_uptime_ms() -> Integer
    mapper xstd_request_count() -> Integer
    mapper xstd_module_info(which: Integer) -> String
    consumer xstd_mark_start()
}

// Resident set size in bytes — what the process occupies in RAM right now.
mapper rss() -> Integer => xstd_mem_rss()

// High-water mark of resident memory in bytes, since the process started.
mapper peakRss() -> Integer => xstd_mem_peak()

// Milliseconds since the process started.
mapper uptimeMs() -> Integer => xstd_uptime_ms()

// Requests served by the built-in web server.
mapper requests() -> Integer => xstd_request_count()

// Module identity from the module block: 0 = id, 1 = name, 2 = version.
mapper info(which: Integer) -> String => xstd_module_info(which)

// Reset the uptime origin — call at the top of `entry` to measure uptime from
// your own start rather than from first use.
consumer markStart() { xstd_mark_start() }

// Every reading as one Json object.
producer snapshot() -> Json {
    let o = json.object()
    o = json.set(o, "rssBytes", json.int(rss()))
    o = json.set(o, "peakRssBytes", json.int(peakRss()))
    o = json.set(o, "uptimeMs", json.int(uptimeMs()))
    o = json.set(o, "requests", json.int(requests()))
    return o
}
