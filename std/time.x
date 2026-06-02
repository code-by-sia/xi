// std/time — monotonic clock & sleep.  import "std/time.x"  then  time.nowNanos()
namespace time

extern "C" {
    mapper   xstd_now_nanos() -> Integer
    consumer xstd_sleep_ms(ms: Integer)
}

// Monotonic nanoseconds since program start.
mapper nowNanos() -> Integer { return xstd_now_nanos() }
mapper nowMillis() -> Integer { return xstd_now_nanos() / 1000000 }
consumer sleepMs(ms: Integer) { xstd_sleep_ms(ms) }
