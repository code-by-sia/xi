// std/monitoring/database — monitoring for the bound QueryProvider.
//
// Knows about both monitoring and query, so neither has to know about the other:
// std/monitoring never mentions a database, and std/query never mentions
// monitoring. Import this when your app has a data source:
//
//     import "std/monitoring/database.xi"
//
//     entry (mon: Monitoring) main(args: String[]) -> Integer {
//         mon.startMonitor()
//         …
//     }
//
// Health is a real round trip: it runs the cheapest possible query against the
// bound provider and reports DOWN if that fails. `queries` counts the checks
// this resource has performed — a provider that wants to report its own numbers
// can implement MonitorableResource itself instead.
import "std/monitoring.xi"
import "std/query.xi"
import "std/json.xi"

class DatabaseMonitoring implements MonitorableResource {
    deps { db: QueryProvider }
    state { probes: Integer = 0, failures: Integer = 0, ready: Bool = false }

    mapper name() -> String => "database"

    // Take one probe up front, so a provider that is unreachable at startup is
    // reported rather than looking healthy until the first request.
    consumer startMonitor() {
        this.ready = true
        probe()
    }

    // The cheapest round trip the contract allows: run an empty plan and see
    // whether the provider answers at all.
    consumer probe() {
        this.probes = this.probes + 1
        let plan = QueryPlan {
            source: "", stages: empty List<QueryStage>, rows: json.array(),
            providerSelf: empty Ptr, providerVtable: empty Ptr
        }
        let rows = db.run(plan)
        if not json.isValid(rows) { this.failures = this.failures + 1 }
    }

    producer healthy() -> Bool {
        if not this.ready { return true }        // not started: nothing to claim
        probe()
        return this.failures == 0
    }

    producer metrics() -> Json {
        let o = json.object()
        o = json.set(o, "provider", json.str(db.name()))
        o = json.set(o, "probes", json.int(this.probes))
        o = json.set(o, "failures", json.int(this.failures))
        return o
    }
}
