# Monitoring - health and metrics

`std/monitoring` is a **mechanism**, not a list of things it knows how to watch.
It defines what a monitor looks like, and loops over every implementation to
build the reports. Each subsystem contributes its own numbers, so the standard
library stays decoupled: `std/monitoring` never mentions HTTP or a data source,
and `std/web` and `std/query` never mention monitoring.

```
std/monitoring.xi            Monitoring, MonitoringRegistry   (imports json only)
std/monitoring/memory.xi     MemoryMonitoring
std/monitoring/cpu.xi        CpuMonitoring
std/monitoring/web.xi        WebMonitoring    + HTTP endpoints
std/monitoring/query.xi      QueryMonitoring  (probes the bound QueryProvider)
std/monitoring/thread.xi     ThreadMonitoring
```

Import only what you use. A batch job importing `std/monitoring/thread.xi` pulls
in no web code, and a program that imports none of them has no monitoring at all.

## Off by default

Monitoring does nothing until you switch it on. Importing a module makes it
*available*, not *running* - including the HTTP endpoints, which answer **404**
while monitoring is off. Enable it in `main`:

```x
import "std/monitoring/memory.xi"
import "std/monitoring/web.xi"
import "std/monitoring/query.xi"

module App {
    id = "billing"
    name = "Billing Service"
    version = "2.1.0"

    entry (mon: MonitoringRegistry as singleton) main(args: String[]) -> Integer {
        mon.enable()                // starts every imported monitor
        web.serve(8080)
        return 0
    }
}
```

`enable()` calls `startMonitor()` on every `Monitoring` implementation - the
query monitor takes its first probe, the memory monitor records its baseline.

Mark the dependency **`as singleton`**. Without it each injection site gets its
own registry, so the one `main` enables is not the one the endpoints answer from,
and everything looks disabled.

Gate it on whatever you like - a flag, an env var, a config field:

```x
entry (mon: MonitoringRegistry as singleton, cfg: AppConfig) main(args: String[]) -> Integer {
    if cfg.monitoringEnabled() { mon.enable() }
    web.serve(8080)
    return 0
}
```

## The two interfaces

```x
// One subsystem that can be watched.
interface Monitoring {
    mapper    name() -> String       // labels it in the reports
    consumer  startMonitor()         // called once, when monitoring is enabled
    producer  healthy() -> Bool      // usable right now? (a producer: may probe)
    producer  metrics() -> Json      // its numbers
}

// Every Monitoring in the program, assembled.
interface MonitoringRegistry {
    consumer  enable()
    predicate isEnabled() -> Bool
    producer  report() -> Json       // uptime + gauges + every monitor
    producer  health() -> Json       // {"status": …, "checks": {…}}
    producer  healthy() -> Bool
}
```

`healthy()` is a `producer`, not a `predicate`, precisely so a check may do work -
probing a data source is a round trip, not a pure function.

## Adding your own

Implement `Monitoring` and it joins the loop - no registration call, no `bind`:

```x
class CacheMonitoring implements Monitoring {
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

The bundled monitors are not special-cased - each implements exactly this.

| Import | Class | Reports |
|---|---|---|
| `std/monitoring/memory.xi` | `MemoryMonitoring` | `rssBytes`, `peakRssBytes`, `growthBytes` |
| `std/monitoring/cpu.xi` | `CpuMonitoring` | `userMs`, `systemMs`, `busyPercent` |
| `std/monitoring/web.xi` | `WebMonitoring` | `requests` served |
| `std/monitoring/query.xi` | `QueryMonitoring` | `provider`, `probes`, `failures`; health runs a real query |
| `std/monitoring/thread.xi` | `ThreadMonitoring` | `spawned`, `live` |

`MemoryMonitoring` and `ThreadMonitoring` accept a ceiling (`maxRssBytes`,
`maxLive`); leave it `0` and they report numbers without ever claiming unhealthy.

## Reporting things directly

For something the app already knows, push it - no class needed:

```x
monitor.status("migrations", done)     // joins the health report
monitor.gauge("queueDepth", n)         // joins the metrics
```

Setting the same name again updates it in place. A status reported `false` takes
overall health down, exactly like a failing monitor.

Process readings are always available, whether or not monitoring is enabled:

| Function | Returns |
|---|---|
| `monitor.rss()` / `monitor.peakRss()` | resident / peak bytes |
| `monitor.uptimeMs()` | milliseconds since start |
| `monitor.info(n)` | module `id` (0), `name` (1), `version` (2) |
| `monitor.snapshot()` | uptime + reported gauges |
| `monitor.markStart()` | reset the uptime origin |

`rss` is read from the OS (`task_info` on macOS, `/proc/self/statm` on Linux), so
it reflects what the process actually occupies.

## Reading the reports

Inject `MonitoringRegistry` anywhere:

```x
scheduled heartbeat() cron "0 * * * * *" {
    logger.info(json.stringify(mon.report()))
}
```

## HTTP endpoints

`std/monitoring/web.xi` ships a controller that exposes the reports. It
auto-registers like any `WebRequestHandler`, and is live only while monitoring is
enabled:

| Endpoint | Returns |
|---|---|
| `GET /monitor/health` | `{"status":"UP","checks":{…}}`, **503** when `DOWN`, **404** when disabled |
| `GET /monitor/info` | module `id`, `name`, `version` |
| `GET /monitor/metrics` | uptime, gauges, and every monitor |

```console
$ curl localhost:8080/monitor/health
{"status":"UP","checks":{"memory":"UP","cpu":"UP","web":"UP","query":"UP","threads":"UP"}}

$ curl localhost:8080/monitor/metrics
{"uptimeMs":2046,"memory":{"rssBytes":1900544,"peakRssBytes":1900544,"growthBytes":98304},
 "cpu":{"userMs":1,"systemMs":2,"busyPercent":0},"web":{"requests":3},
 "query":{"provider":"memory","probes":7,"failures":0},"threads":{"spawned":0,"live":0}}
```

Your own controllers keep working alongside it - each request goes to the one
whose `where` guard matches.

**Want a different shape?** The controller is optional. Inject
`MonitoringRegistry` into a controller of your own for different paths, auth, or
a subset - `health()` and `report()` hand you the same Json:

```x
class OpsController implements WebRequestHandler {
    deps { mon: MonitoringRegistry as singleton }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/healthz" {
        if mon.healthy() { res.sendText(200, "ok") } else { res.sendText(503, "unhealthy") }
    }
}
```

See `examples/web/monitor_demo.xi` for a runnable service.
