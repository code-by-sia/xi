// std/monitoring: several Monitoring implementations, looped over by the
// registry, and off until enabled. Nothing here imports web or query —
// monitoring is decoupled from the subsystems that contribute to it.
import "std/monitoring/memory.xi"
import "std/monitoring/cpu.xi"
import "std/monitoring.xi"
import "std/json.xi"

class CacheMonitoring implements Monitoring {
    deps {}
    state { started: Bool = false }
    mapper    name() -> String => "cache"
    consumer  startMonitor() { this.started = true }
    producer  healthy() -> Bool => this.started      // only healthy once started
    producer  metrics() -> Json {
        let o = json.object()
        return json.set(o, "entries", json.int(7))
    }
}

class QueueMonitoring implements Monitoring {
    deps {}
    mapper    name() -> String => "queue"
    consumer  startMonitor() { }
    producer  healthy() -> Bool => true
    producer  metrics() -> Json {
        let o = json.object()
        return json.set(o, "depth", json.int(3))
    }
}

module App {
    id = "monitoring_test"     // matches the file name so `xt` finds the binary
    name = "Monitoring Test"
    version = "5.5.5"
}

test "process readings are available directly" {
    assert monitor.rss() > 0
    assert monitor.peakRss() >= monitor.rss()
    assert monitor.uptimeMs() >= 0
}

test "module identity comes from the module block" {
    assertEq(monitor.info(0), "monitoring_test")
    assertEq(monitor.info(1), "Monitoring Test")
    assertEq(monitor.info(2), "5.5.5")
}

test "monitoring is off until enabled" (mon: MonitoringRegistry as singleton) {
    assert not mon.isEnabled()
    assertEq(json.getString(mon.health(), "status"), "DISABLED")
    assertEq(json.length(mon.report()), 0)       // reports nothing while off
}

test "enable starts every monitor and the registry loops them" (mon: MonitoringRegistry as singleton) {
    mon.enable()
    assert mon.isEnabled()
    let r = mon.report()
    // each implementation contributes under its own name
    assertEq(json.asNumber(json.get(json.get(r, "cache"), "entries")), 7.0)
    assertEq(json.asNumber(json.get(json.get(r, "queue"), "depth")), 3.0)
    assert json.asNumber(json.get(json.get(r, "memory"), "rssBytes")) > 0.0
    assert json.has(json.get(r, "cpu"), "userMs")
    assert json.has(r, "uptimeMs")
}

test "startMonitor reaches every monitor" (mon: MonitoringRegistry as singleton) {
    // CacheMonitoring is unhealthy until started, so UP proves the loop ran it —
    // and that one shared registry is doing the reporting.
    mon.enable()
    assert mon.healthy()
    assertEq(json.getString(json.get(mon.health(), "checks"), "cache"), "UP")
}

test "reported gauges and statuses join the reports" (mon: MonitoringRegistry as singleton) {
    mon.enable()
    monitor.gauge("widgets", 12)
    assertEq(json.asNumber(json.get(mon.report(), "widgets")), 12.0)
    monitor.gauge("widgets", 30)                 // same name updates in place
    assertEq(json.asNumber(json.get(mon.report(), "widgets")), 30.0)

    monitor.status("migrations", false)          // a status can take health down
    assert not mon.healthy()
    assertEq(json.getString(mon.health(), "status"), "DOWN")
    monitor.status("migrations", true)
    assert mon.healthy()
}
