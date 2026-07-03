// =============================================================
// X — User greeting service (from spec Section 15)
// =============================================================

// --- refined types ---
type Age   = Number where value >= 0 and value <= 130
type Email = String where value matches /^[^@\s]+@[^@\s]+\.[^@\s]+$/
type Name  = String where value.length > 0

// --- compound type ---
type User = { name: Name, age: Age, email: Email }

// --- interfaces ---
interface Logger {
    async consumer log(level: String, msg: String)
}

interface UserRepository {
    async mapper findById(id: String) -> User?
}

interface Greeter {
    mapper greet(user: User) -> String
}

interface Formatter {
    mapper format(name: Name) -> String
}

// --- pure functions ---
predicate isAdult(user: User) {
    return user.age >= 18
}

projector emailOf(user: User) -> Email {
    return user.email
}

// --- classes ---
class ConsoleLogger implements Logger {
    deps {}

    async consumer log(level: String, msg: String) {
        system.stdout.writeln("[" + level + "] " + msg)
    }
}

class CasualFormatter implements Formatter {
    deps {}
    mapper format(name: Name) -> String { return "Hey " + name + "!" }
}

class FormalFormatter implements Formatter {
    deps {}
    mapper format(name: Name) -> String { return "Good day, " + name + "." }
}

class TieredGreeter implements Greeter {
    deps {
        logger: Logger,
        formatter: Formatter when {
            input.age < 18 -> CasualFormatter,
            otherwise      -> FormalFormatter
        }
    }

    mapper greet(user: User) -> String {
        return formatter.format(user.name)
    }
}

// --- module ---
module App {
    bind Logger    -> ConsoleLogger  as singleton
    bind Greeter   -> TieredGreeter  as transient
    bind Formatter -> FormalFormatter as transient
}

// --- entry point ---
async entry (logger: Logger) main(args: String[]) -> Integer {
    let greeter = App.resolve(Greeter)
    let user = User { name: "John Doe", age: 36, email: "ada@example.com" }
    if isAdult(user) {
        logger.log("info", greeter.greet(user))
    }
    return 0
}
