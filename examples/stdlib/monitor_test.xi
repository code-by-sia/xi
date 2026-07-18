// std/monitor: process readings, module identity, and health-check collection.
//
// The endpoints themselves need a running server (see
// examples/web/monitor_demo.xi); this covers the parts that are testable
// in-process, including the `HealthCheck[]` collection that mounts them.
import "std/monitor.xi"
import "std/json.xi"

class UpCheck implements HealthCheck {
    deps {}
    mapper    name() -> String => "up-one"
    predicate healthy() -> Bool => true
}

class AlsoUpCheck implements HealthCheck {
    deps {}
    mapper    name() -> String => "up-two"
    predicate healthy() -> Bool => true
}

// A collector standing in for MonitorController: every HealthCheck implementor
// is injected, and each is reachable through the interface. (Injected by its
// own interface — methods dispatch through the vtable.)
interface Collecting {
    projector count() -> Integer
    producer  names() -> String
    predicate allUp() -> Bool
}

class Collector implements Collecting {
    deps { checks: HealthCheck[] }
    projector count() -> Integer => checks.len
    producer  names() -> String {
        let out = ""
        for c in checks { out = out + c.name() + ";" }
        return out
    }
    predicate allUp() -> Bool {
        for c in checks { if not c.healthy() { return false } }
        return true
    }
}

module App {
    id = "monitor_test"        // matches the file name so `xt` finds the binary
    name = "Monitor Test"
    version = "9.9.9"
}

test "process readings are present and sane" {
    assert monitor.rss() > 0                 // resident memory is real
    assert monitor.peakRss() >= monitor.rss()
    assert monitor.uptimeMs() >= 0
    assertEq(monitor.requests(), 0)          // nothing served in a test binary
}

test "module identity comes from the module block" {
    assertEq(monitor.info(0), "monitor_test")
    assertEq(monitor.info(1), "Monitor Test")
    assertEq(monitor.info(2), "9.9.9")
}

test "snapshot carries every reading" {
    let s = monitor.snapshot()
    assert json.isValid(s)
    assert json.asNumber(json.get(s, "rssBytes")) > 0.0
    assert json.has(s, "peakRssBytes")
    assert json.has(s, "uptimeMs")
    assert json.has(s, "requests")
}

test "every HealthCheck implementor is collected and dispatchable" (c: Collecting) {
    assertEq(c.count(), 2)                   // both classes injected, no bind
    assertEq(c.names(), "up-one;up-two;")    // vtable dispatch through the array
    assert c.allUp()
}
