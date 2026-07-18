// std/monitoring/cpu — process CPU time as a Monitoring implementation.
//
//     import "std/monitoring/cpu.xi"
//
// Reports the CPU milliseconds this process has consumed, split into user and
// system, plus `busyPercent`: CPU time over wall time since monitoring was
// enabled. On a multi-core machine that can exceed 100, which is the honest
// answer — it means more than one core's worth of work.
//
// Read from getrusage, so these are real accounting numbers rather than a
// sampled estimate.
import "std/monitoring.xi"
import "std/json.xi"

extern "C" {
    mapper xstd_cpu_user_ms() -> Integer
    mapper xstd_cpu_system_ms() -> Integer
}

class CpuMonitoring implements Monitoring {
    deps {}
    // Baselines taken when monitoring is enabled, so the percentage covers the
    // monitored window rather than including process startup.
    state { startUser: Integer = 0, startSystem: Integer = 0, startUptime: Integer = 0 }

    mapper name() -> String => "cpu"

    consumer startMonitor() {
        this.startUser = xstd_cpu_user_ms()
        this.startSystem = xstd_cpu_system_ms()
        this.startUptime = monitor.uptimeMs()
    }

    producer healthy() -> Bool => true      // CPU use is a number, not a verdict

    producer metrics() -> Json {
        let user = xstd_cpu_user_ms()
        let sys = xstd_cpu_system_ms()
        let elapsed = monitor.uptimeMs() - this.startUptime
        let busy = (user - this.startUser) + (sys - this.startSystem)
        let o = json.object()
        o = json.set(o, "userMs", json.int(user))
        o = json.set(o, "systemMs", json.int(sys))
        if elapsed > 0 { o = json.set(o, "busyPercent", json.int(busy * 100 / elapsed)) }
        return o
    }
}
