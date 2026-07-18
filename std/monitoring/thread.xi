// std/monitoring/thread — monitoring for spawned threads.
//
// Knows about both monitoring and threading, so neither has to know about the
// other. Import it when your app spawns work:
//
//     import "std/monitoring/thread.xi"
//
//     entry (mon: Monitoring) main(args: String[]) -> Integer {
//         mon.startMonitor()
//         …
//     }
//
// Reports how many threads have been spawned and how many are still running,
// under "threads". Health is `true` unless you set an expected ceiling with
// `maxLive` — useful to notice a pool that never drains.
import "std/monitoring.xi"
import "std/json.xi"

extern "C" {
    mapper xstd_thread_spawned_count() -> Integer
    mapper xstd_thread_live_count() -> Integer
}

class ThreadMonitoring implements Monitoring {
    deps {}
    // 0 = no ceiling: report the numbers, never claim unhealthy.
    state { maxLive: Integer = 0 }

    mapper name() -> String => "threads"
    consumer startMonitor() { }               // the counters run with the runtime

    producer healthy() -> Bool {
        if this.maxLive <= 0 { return true }
        return xstd_thread_live_count() <= this.maxLive
    }

    producer metrics() -> Json {
        let o = json.object()
        o = json.set(o, "spawned", json.int(xstd_thread_spawned_count()))
        o = json.set(o, "live", json.int(xstd_thread_live_count()))
        return o
    }
}
