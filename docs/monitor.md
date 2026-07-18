# Monitor - health, memory and metrics

`std/monitor` reports on the running process: resident memory, uptime, requests
served, and the health of the things your app depends on. In a web app it also
mounts a set of read-only endpoints, so a load balancer or dashboard can poll the
service without an external agent.

```x
import "std/monitor.xi"

monitor.rss()          // resident bytes right now
monitor.peakRss()      // high-water mark
monitor.uptimeMs()     // since process start
monitor.requests()     // requests the built-in server has served
```

## Endpoints

`MonitorController` is a `WebRequestHandler`, and controllers auto-register, so
**importing the module is all it takes** - no `bind`, no handler code:

```x
import "std/monitor.xi"
import "std/web.xi"

module App {
    id = "billing"
    name = "Billing Service"
    version = "2.1.0"
    entry main(args: String[]) -> Integer { web.serve(8080) return 0 }
}
```

| Endpoint | Returns |
|---|---|
| `GET /monitor/health` | `{"status":"UP"}`, or `DOWN` with **503** if any check fails |
| `GET /monitor/info` | the module's `id`, `name` and `version` |
| `GET /monitor/memory` | `rssBytes`, `peakRssBytes`, `uptimeMs` |
| `GET /monitor/metrics` | the above plus `requests` |

```console
$ curl localhost:8080/monitor/info
{"id":"billing","name":"Billing Service","version":"2.1.0"}

$ curl localhost:8080/monitor/metrics
{"rssBytes":1900544,"peakRssBytes":1900544,"uptimeMs":41,"requests":3}
```

`info` is filled in by the compiler from the [module block](multi-file.md#module-fields),
so it always matches what you shipped.

Your own controllers keep working alongside these - every `WebRequestHandler` is
registered, and each request goes to the one whose `where` guard matches.

## Health checks

A `HealthCheck` reports one dependency. Implement it and **every implementor is
collected automatically** - no registry, no bind:

```x
class DatabaseCheck implements HealthCheck {
    deps { db: QueryProvider }
    mapper    name() -> String => "database"
    predicate healthy() -> Bool => db.ping()
}
```

```console
$ curl -i localhost:8080/monitor/health
HTTP/1.1 503 Service Unavailable
{"status":"DOWN","checks":{"database":"DOWN","queue":"UP"}}
```

The overall `status` is `UP` only when every check passes; one failure turns the
response `DOWN` and the status code **503**, which is what a load balancer wants
to see before taking an instance out of rotation.

## Reading the numbers yourself

Every reading is available as a plain value, and `snapshot()` bundles them:

| Function | Returns |
|---|---|
| `monitor.rss()` | resident set size, bytes |
| `monitor.peakRss()` | peak resident size, bytes |
| `monitor.uptimeMs()` | milliseconds since start |
| `monitor.requests()` | requests served by the built-in server |
| `monitor.info(n)` | module `id` (0), `name` (1), `version` (2) |
| `monitor.snapshot()` | all of the above as a `Json` object |
| `monitor.markStart()` | reset the uptime origin to now |

Use them to log a periodic line, feed a [scheduled job](language-guide.md), or
assert on memory in a test:

```x
import "std/monitor.xi"

scheduled heartbeat() cron "0 * * * * *" {
    logger.info("rss=" + monitor.rss() + " uptime=" + monitor.uptimeMs())
}
```

`rss` is read from the OS (`task_info` on macOS, `/proc/self/statm` on Linux), so
it reflects what the process actually occupies, not what an allocator thinks it
handed out.

See `examples/web/monitor_demo.xi` for a runnable service.
