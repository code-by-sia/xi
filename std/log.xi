// std/log — a leveled Logger interface with a console default.  import "std/log.xi"
//
// `Logger` is un-namespaced so you can inject it with a bare name anywhere deps
// are wired — classes, functions, and `entry`:
//
//     async entry (logger: Logger) main(args: String[]) -> Integer {
//         logger.info("starting up")
//         logger.warn("low on disk")
//         logger.error("request failed")
//         return 0
//     }
//
// Levels: debug < info < warn < error < fatal, plus `audit` for an explicit
// trail and `print` for unprefixed output. Diagnostics (warn/error/fatal) go to
// stderr; the rest go to stdout. ConsoleLogger is the default (the sole
// implementor, so DI picks it); bind your own `Logger` to redirect output
// (files, structured logs, a test buffer, ...).

interface Logger {
    consumer print(msg: String)    // unprefixed line (stdout)
    consumer debug(msg: String)    // verbose diagnostics (stdout)
    consumer info(msg: String)     // normal operation (stdout)
    consumer warn(msg: String)     // something looks off (stderr)
    consumer error(msg: String)    // an operation failed (stderr)
    consumer fatal(msg: String)    // unrecoverable condition (stderr)
    consumer audit(msg: String)    // security/compliance trail (stdout)
}

class ConsoleLogger implements Logger {
    deps {}
    consumer print(msg: String) { system.stdout.writeln(msg) }
    consumer debug(msg: String) { system.stdout.writeln("[debug] " + msg) }
    consumer info(msg: String)  { system.stdout.writeln("[info] " + msg) }
    consumer warn(msg: String)  { system.stderr.writeln("[warn] " + msg) }
    consumer error(msg: String) { system.stderr.writeln("[error] " + msg) }
    consumer fatal(msg: String) { system.stderr.writeln("[fatal] " + msg) }
    consumer audit(msg: String) { system.stdout.writeln("[audit] " + msg) }
}
