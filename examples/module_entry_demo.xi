// The `entry` can live inside its `module` block, alongside the module's
// metadata and `bind`s — handy when a folder holds several modules (each builds
// to its own binary with `xc --all`). A top-level `entry` + `module App {}` also
// works; this shows the inline form.
//
//   xc examples/module_entry_demo.xi && ./build/module_entry_demo
import "std/log.xi"

interface Greeter { mapper greet() -> String }
class Hi implements Greeter { deps {} mapper greet() -> String { return "hello from a module-scoped entry" } }

module App {
    id      = "module_entry_demo"      // name of the compiled binary
    name    = "Module Entry Demo"
    version = "0.1.0"
    license = "MIT"

    // `entry` always returns Integer: `-> Integer` is optional and a body
    // without `return` exits 0.
    async entry (logger: Logger, greeter: Greeter) main(args: String[]) {
        logger.info(greeter.greet())
    }
}
