// std/log — a Logger injected by DI, including into `entry`. ConsoleLogger is the
// default; bind your own Logger to redirect output without touching callers.
//
//   xc examples/logger_demo.xi && ./build/logger_demo
import "std/log.xi"

interface Greeter { consumer greet(name: String) }
class LogGreeter implements Greeter {
    deps { logger: Logger }                       // Logger wired in automatically
    consumer greet(name: String) { logger.print("Hi, " + name) }
}

// `entry` can declare deps too — they're DI-resolved before the body runs.
async entry { logger: Logger, greeter: Greeter } main(args: String[]) -> Integer {
    logger.print("Hello World!")
    greeter.greet("Ada")
    logger.error("(this line goes to stderr)")
    return 0
}

module App {}
