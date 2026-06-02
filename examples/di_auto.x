// Automatic dependency injection.
//
// No `bind` is required: the compiler discovers implementations automatically.
// A `bind` (in a module) is only an optional override. When an interface has
// several implementations, a dependency disambiguates with:
//   * a `where` guard,           calc: Calculator where calc.precise()
//   * a list type,               rules: TaxRule[]
//   * an `or` fallback,          repo: Repository or EmptyRepository
// Functions can declare dependencies too:  kind { dep: I } name(params).

interface Logger { consumer log(msg: String) }
class ConsoleLogger implements Logger {
    deps {}
    consumer log(msg: String) { system.stdout.writeln(msg) }
}

interface Calculator { predicate precise() }
class BasicCalc   implements Calculator { deps {} predicate precise() { return false } }
class PreciseCalc implements Calculator { deps {} predicate precise() { return true } }

interface TaxRule { mapper rate() -> Number }
class Vat implements TaxRule { deps {} mapper rate() -> Number { return 20 } }
class Gst implements TaxRule { deps {} mapper rate() -> Number { return 5 } }

interface Repository { mapper name() -> String }
class EmptyRepository implements Repository { deps {} mapper name() -> String { return "empty" } }
class SqlRepository   implements Repository { deps {} mapper name() -> String { return "sql" } }

// Foo's deps are all auto-resolved, each with its own disambiguation rule.
interface Service { consumer run() }
class Foo implements Service {
    deps {
        logger: Logger
        calc:   Calculator where calc.precise()
        rules:  TaxRule[]
        repo:   Repository or EmptyRepository
    }
    consumer run() {
        logger.log("precise calculator? " + calc.precise())
        logger.log("tax rules found    = " + rules.len)
        logger.log("repository         = " + repo.name())
    }
}

// A function with its own dependency block.
mapper { logger: Logger } describe(name: String) -> String {
    logger.log("describing " + name)
    return "<" + name + ">"
}

async entry main(args: String[]) -> Integer {
    let svc = App.resolve(Service)   // auto-wired; no bind needed
    svc.run()
    system.stdout.writeln(describe("widget"))
    return 0
}

module App {}   // empty: resolution is automatic. Add binds here only to steer.
