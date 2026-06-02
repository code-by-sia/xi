// Logging service.
namespace logging

interface Logger { consumer log(msg: String) }

class ConsoleLogger implements Logger {
    deps {}
    consumer log(msg: String) { system.stdout.writeln("[log] " + msg) }
}
