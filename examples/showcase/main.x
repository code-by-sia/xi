// Showcase entry point. `main` aggregates the project's imports; each module
// lives in its own small file under model/ rules/ services/ util/.

import "model/types.x"
import "rules/classify.x"
import "services/logger.x"
import "services/format.x"
import "services/audit.x"
import "services/greeter.x"
import "util/parse.x"
import "std/text.x"
import "std/convert.x"

consumer report(label: String, r: model.Age!) {
    if isOk(r) { system.stdout.writeln(label + " -> age " + r.value) }
    else       { system.stdout.writeln(label + " -> " + r.err) }
}

async entry main(args: String[]) -> Integer {
    let greeter = App.resolve(greet.Greeter)        // auto-wired

    let alice = model.makeUser("Alice", 30, "alice@example.com")
    system.stdout.writeln(greeter.greet(alice))
    system.stdout.writeln(text.toUpper(alice.name) + " is " + rules.classify(alice))

    report("42",   util.parseAge("42"))
    report("999",  util.parseAge("999"))
    report("oops", util.parseAge("oops"))

    let code = 2
    match code {
        1 -> { system.stdout.writeln("one") }
        2 -> { system.stdout.writeln("two") }
        n -> { system.stdout.writeln("many: " + n) }
    }
    return 0
}

module App {}   // empty: DI is automatic.
