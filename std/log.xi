// std/log — a Logger interface with a console default.  import "std/log.xi"
//
// `Logger` is un-namespaced so you can inject it with a bare name anywhere deps
// are wired — classes, functions, and `entry`:
//
//     async entry { logger: Logger } main(args: String[]) -> Integer {
//         logger.print("Hello, world!")
//         return 0
//     }
//
// ConsoleLogger is the default (the sole implementor, so DI picks it); bind your
// own `Logger` to redirect output (files, structured logs, a test buffer, ...).

interface Logger {
    consumer print(msg: String)
    consumer error(msg: String)
}

class ConsoleLogger implements Logger {
    deps {}
    consumer print(msg: String) { system.stdout.writeln(msg) }
    consumer error(msg: String) { system.stderr.writeln("[error] " + msg) }
}
