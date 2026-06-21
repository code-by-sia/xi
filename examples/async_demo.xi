// async / await / await all — concurrent functions backed by worker threads.
// An `async` function (or one returning `Future<T>`) runs on its own thread when
// called and yields a Future immediately; `await` blocks for the result.
//
//   xc examples/async_demo.xi && ./build/async_demo
import "std/log.xi"
import "std/convert.xi"
import "std/time.xi"

// `async <kind>` — the call returns Future<Integer>; the body returns the inner T.
async producer work(label: Integer) -> Integer {
    time.sleepMs(100)                // pretend this is slow I/O
    return label * label
}

// The `async` keyword is what makes a call run on a worker. (A `-> Future<T>`
// return type instead means the function *returns a future it built* — see
// examples/delay_demo.xi.)
async mapper fetch(id: Integer) -> Integer {
    return id + 1000
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    // Two awaits, run sequentially.
    logger.info("work(6)  = " + await work(6))     // 36
    logger.info("fetch(7) = " + await fetch(7))    // 1007

    // Fan out, then `await all` — the three run concurrently (~100ms total).
    let t0 = time.nowMillis()
    let jobs = listOf(work(2), work(3), work(4))   // all three threads started here
    let done = await all jobs                       // List<Integer>, joined in order
    logger.info("all      = " + done.joinToString(", ") { int_to_string(it) })  // 4, 9, 16
    logger.info("elapsed  = " + (time.nowMillis() - t0) + "ms (concurrent)")
    return 0
}

module App {}
