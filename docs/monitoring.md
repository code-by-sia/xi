# Monitoring - health and metrics

`std/monitoring` is a **mechanism**, not a list of things it knows how to watch.
It defines what a monitorable thing looks like and collects whatever implements
it; each subsystem contributes its own numbers. That keeps the standard library
decoupled - `std/monitoring` never mentions HTTP or databases, and `std/web` and
`std/query` never mention monitoring.

```
std/monitoring.xi            MonitorableResource, Monitoring   (knows nothing else)
std/monitoring/web.xi        WebMonitoring       + endpoints   (monitoring + web)
std/monitoring/database.xi   DatabaseMonitoring                (monitoring + query)
std/monitoring/thread.xi     ThreadMonitoring                  (monitoring + threads)
```

You import the bridge for what you actually use. A batch job importing
`std/monitoring/thread.xi` pulls in no web code at all.

## Turning it on

Monitoring is **opt-in**: nothing runs until you ask it to, in `main`.

```x
import "std/monitoring/web.xi"
import "std/monitoring/database.xi"

module App {
    id = "billing"
    name = "Billing Service"
    version = "2.1.0"

    entry (mon: Monitoring as singleton) main(args: String[]) -> Integer {
        mon.startMonitor()          // start every imported resource
        web.serve(8080)
            return 0
    }
}
```

`startMonitor()` calls `startMonitor()` on every `MonitorableResource` in the
program - a database opens its probe, a pool records its baseline. Mark the
dependency `as singleton` so the registry you start is the one that reports;
without it each injection site would get its own, unstarted copy.

## The interfaces

```x
interface MonitorableResource {
    mapper    name() -> String       // labels it in the reports
    consumer  startMonitor()         // called once, from Monitoring.startMonitor()
    producer  healthy() -> Bool      // usable right now? (a producer: may probe)
    producer  metrics() -> Json      // its numbers
}

interface Monitoring {
    consumer  startMonitor()
    producer  report() -> Json       // process readings + gauges + every resource
    producer  health() -> Json       // {"status": …, "checks": {…}}
    producer  healthy() -> Bool
}
```

Implement `MonitorableResource` and it joins the reports - no registration call,
no `bind`:

```x
class CacheMonitoring implements MonitorableResource {
    deps { cache: Cache }
    mapper    name() -> String => "cache"
    consumer  startMonitor() { }
    producer  healthy() -> Bool => cache.reachable()
    producer  metrics() -> Json {
        let o = json.object()
        return json.set(o, "entries", json.int(cache.size()))
    }
}
```

`healthy()` is a `producer`, not a `predicate`, precisely so a check may do work -
a database probe is a round trip, not a pure function.

## The bundled resources

| Import | Resource | Reports |
|---|---|---|
| `std/monitoring/web.xi` | `WebMonitoring` | `requests` served |
| `std/monitoring/database.xi` | `DatabaseMonitoring` | `provider`, `probes`, `failures`; health runs a real query |
| `std/monitoring/thread.xi` | `ThreadMonitoring` | `spawned`, `live` |

None of these is special-cased: each implements the same interface your own code
would.

## Reporting things directly

For something the app already knows, push it - no class needed:

```x
monitor.status("migrations", done)     // joins the health report
monitor.gauge("queueDepth", n)         // joins the metrics
```

Setting the same name again updates it in place. A reported status that is
`false` takes overall health down, exactly like a failing resource.

## Reading the reports

Inject `Monitoring` anywhere and use `report()` / `health()`:

```x
scheduled heartbeat() cron "0 * * * * *" {
    logger.info(json.stringify(mon.report()))
}
```

Process readings are also available directly:

| Function | Returns |
|---|---|
| `monitor.rss()` / `monitor.peakRss()` | resident / peak bytes |
| `monitor.uptimeMs()` | milliseconds since start |
| `monitor.info(n)` | module `id` (0), `name` (1), `version` (2) |
| `monitor.snapshot()` | process readings + reported gauges |
| `monitor.markStart()` | reset the uptime origin |

`rss` is read from the OS (`task_info` on macOS, `/proc/self/statm` on Linux), so
it reflects what the process actually occupies.

## HTTP endpoints

`std/monitoring/web.xi` ships a controller that exposes the reports. It
auto-registers like any `WebRequestHandler`, so importing the module is enough:

| Endpoint | Returns |
|---|---|
| `GET /monitor/health` | `{"status":"UP","checks":{…}}`, **503** when `DOWN` |
| `GET /monitor/info` | module `id`, `name`, `version` |
| `GET /monitor/memory` | `rssBytes`, `peakRssBytes`, `uptimeMs` |
| `GET /monitor/metrics` | the above plus every resource |

```console
$ curl localhost:8080/monitor/health
{"status":"UP","checks":{"web":"UP","database":"UP","threads":"UP","cache":"UP"}}

$ curl localhost:8080/monitor/metrics
{"rssBytes":1900544,"peakRssBytes":1900544,"uptimeMs":41,"workers":4,
 "web":{"requests":2},"database":{"provider":"memory","probes":4,"failures":0},
 "threads":{"spawned":0,"live":0},"cache":{"entries":42}}
```

Your own controllers keep working alongside it - each request goes to the one
whose `where` guard matches.

**Want a different shape?** The controller is optional. Inject `Monitoring` into
a controller of your own and build whatever you like - different paths, auth, a
subset of the data. `mon.health()` and `mon.report()` hand you the same Json:

```x
class OpsController implements WebRequestHandler {
    deps { mon: Monitoring as singleton }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/healthz" {
        if mon.healthy() { res.sendText(200, "ok") } else { res.sendText(503, "unhealthy") }
    }
}
```

See `examples/web/monitor_demo.xi` for a runnable service.
