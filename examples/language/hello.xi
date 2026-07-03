// Hello, world in Ξ.
//
// `Logger` comes from the standard library; writing `{ logger: Logger }` on the
// entry asks for it by interface and the compiler injects the default
// (ConsoleLogger) — no setup, no globals. Swap in your own Logger later and this
// code doesn't change.
import "std/log.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.print("Hello World!")
    return 0
}
