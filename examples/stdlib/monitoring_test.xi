// std/monitoring: the mechanism — process readings, reported status/gauges, and
// MonitorableResource collection. Nothing here imports web or query: monitoring
// is decoupled from the subsystems that contribute to it.
import "std/monitoring.xi"
import "std/json.xi"

class CacheResource implements MonitorableResource {
    deps {}
    state { started: Bool = false }
    mapper    name() -> String => "cache"
    consumer  startMonitor() { this.started = true }
    producer  healthy() -> Bool => this.started      // only healthy once started
    producer  metrics() -> Json {
        let o = json.object()
        o = json.set(o, "entries", json.int(7))
        return o
    }
}

class QueueResource implements MonitorableResource {
    deps {}
    mapper    name() -> String => "queue"
    consumer  startMonitor() { }
    producer  healthy() -> Bool => true
    producer  metrics() -> Json {
        let o = json.object()
        o = json.set(o, "depth", json.int(3))
        return o
    }
}

module App {
    id = "monitoring_test"     // matches the file name so `xt` finds the binary
    name = "Monitoring Test"
    version = "5.5.5"
}

test "process readings are present and sane" {
    assert monitor.rss() > 0
    assert monitor.peakRss() >= monitor.rss()
    assert monitor.uptimeMs() >= 0
}

test "module identity comes from the module block" {
    assertEq(monitor.info(0), "monitoring_test")
    assertEq(monitor.info(1), "Monitoring Test")
    assertEq(monitor.info(2), "5.5.5")
}

test "reported gauges join the report" (mon: Monitoring as singleton) {
    monitor.gauge("widgets", 12)
    let r = mon.report()
    assertEq(json.asNumber(json.get(r, "widgets")), 12.0)
    monitor.gauge("widgets", 30)                 // same name updates in place
    assertEq(json.asNumber(json.get(mon.report(), "widgets")), 30.0)
}

test "every resource contributes its metrics" (mon: Monitoring as singleton) {
    let r = mon.report()
    assertEq(json.asNumber(json.get(json.get(r, "cache"), "entries")), 7.0)
    assertEq(json.asNumber(json.get(json.get(r, "queue"), "depth")), 3.0)
    assert json.has(r, "rssBytes")               // process readings still there
}

test "startMonitor starts every resource" (mon: Monitoring as singleton) {
    // CacheResource reports unhealthy until started, so this proves the call
    // reached it — and that one shared registry is doing the reporting.
    mon.startMonitor()
    assert mon.healthy()
    assertEq(json.getString(mon.health(), "status"), "UP")
    assertEq(json.getString(json.get(mon.health(), "checks"), "cache"), "UP")
}

test "a reported status can take health down" (mon: Monitoring as singleton) {
    mon.startMonitor()
    monitor.status("migrations", false)
    assert not mon.healthy()
    assertEq(json.getString(mon.health(), "status"), "DOWN")
    assertEq(json.getString(json.get(mon.health(), "checks"), "migrations"), "DOWN")
    monitor.status("migrations", true)           // recovers
    assert mon.healthy()
}
