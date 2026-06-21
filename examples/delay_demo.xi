// runWithDelay(ms) { … } — run a block after a delay on a worker thread.
// It returns a Future immediately (so the caller keeps going) and is awaitable.
// The block captures the enclosing function's params and deps by value.
//
//   xc examples/delay_demo.xi && ./build/delay_demo
import "std/log.xi"
import "std/convert.xi"
import "std/time.xi"

// A function that returns the future built by runWithDelay (a `-> Future<T>`
// return type means "returns a future value" — it is not auto-spawned).
producer (logger: Logger) ping(name: String, ms: Integer) -> Future<Integer> {
    return runWithDelay(ms) { logger.info("ping " + name) }
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let t0 = time.nowMillis()

    // fire-and-await a single delayed block (captures `logger`)
    let f = runWithDelay(150) { logger.info("yo (after 150ms)") }
    logger.info("scheduled; meanwhile doing other work…")
    await f

    // schedule several and await them together
    await all listOf(ping("alpha", 60), ping("beta", 120))
    logger.info("all fired after " + (time.nowMillis() - t0) + "ms")
    return 0
}

module App {}
