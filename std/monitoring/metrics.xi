// std/monitoring/metrics — the `monitor.*` process readings.
//
// Split from std/monitoring.xi because these live under a namespace
// (`monitor.rss()`), while the interfaces there keep bare names so user code can
// `implements Monitoring` without a prefix. Import std/monitoring.xi —
// it pulls this in.
//
// Everything here is about *this process*: memory, uptime, and whatever the app
// chooses to report. No subsystem — HTTP, database, threads — appears at this
// layer; each of those contributes through the Monitoring interface.
import "std/json.xi"

namespace monitor

extern "C" {
    mapper xstd_mem_rss() -> Integer
    mapper xstd_mem_peak() -> Integer
    mapper xstd_uptime_ms() -> Integer
    mapper xstd_module_info(which: Integer) -> String
    consumer xstd_mark_start()
    consumer xstd_mon_set_status(name: String, up: Bool)
    mapper xstd_mon_status_count() -> Integer
    mapper xstd_mon_status_name(i: Integer) -> String
    predicate xstd_mon_status_up(i: Integer) -> Bool
    consumer xstd_mon_set_gauge(name: String, n: Integer)
    mapper xstd_mon_gauge_count() -> Integer
    mapper xstd_mon_gauge_name(i: Integer) -> String
    mapper xstd_mon_gauge_value(i: Integer) -> Integer
}

// ── Process readings ─────────────────────────────────────────────────

// Resident set size in bytes — what the process occupies in RAM right now.
mapper rss() -> Integer => xstd_mem_rss()

// High-water mark of resident memory in bytes, since the process started.
mapper peakRss() -> Integer => xstd_mem_peak()

// Milliseconds since the process started.
mapper uptimeMs() -> Integer => xstd_uptime_ms()

// Module identity from the module block: 0 = id, 1 = name, 2 = version.
mapper info(which: Integer) -> String => xstd_module_info(which)

// Reset the uptime origin — call at the top of `entry` to measure uptime from
// your own start rather than from first use.
consumer markStart() { xstd_mark_start() }

// ── Reporting your own things ────────────────────────────────────────
// monitoring knows only what it is told. Report a status from wherever you
// detect it and it joins the health report; report a number and it joins the
// metrics. Setting the same name again updates it in place.
//
//     monitor.status("migrations", done)
//     monitor.gauge("queueDepth", n)
//
// For something that should be evaluated on every report, implement
// `Monitoring` (std/monitoring.xi) instead.
consumer status(name: String, up: Bool) { xstd_mon_set_status(name, up) }
consumer gauge(name: String, n: Integer) { xstd_mon_set_gauge(name, n) }

// Read back what has been reported (used by the registry; handy in tests).
mapper    statusCount() -> Integer => xstd_mon_status_count()
mapper    statusName(i: Integer) -> String => xstd_mon_status_name(i)
predicate statusUp(i: Integer) -> Bool => xstd_mon_status_up(i)
mapper    gaugeCount() -> Integer => xstd_mon_gauge_count()
mapper    gaugeName(i: Integer) -> String => xstd_mon_gauge_name(i)
mapper    gaugeValue(i: Integer) -> Integer => xstd_mon_gauge_value(i)

// Uptime plus every reported gauge. Memory is not included here — it comes from
// MemoryMonitoring, so it is opt-in like every other subsystem. The registry in
// std/monitoring.xi adds each monitor's metrics on top.
producer snapshot() -> Json {
    let o = json.object()
    o = json.set(o, "uptimeMs", json.int(uptimeMs()))
    let i = 0
    while i < gaugeCount() {
        o = json.set(o, gaugeName(i), json.int(gaugeValue(i)))
        i = i + 1
    }
    return o
}
