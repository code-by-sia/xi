// Calling sibling methods from inside a class — unqualified, like a normal call.
// A method can call any other method of the same class (including private
// helpers not in the interface) and call itself recursively; the compiler
// dispatches them on `self`. No `self.` prefix is required.
//
//   xc examples/self_methods_demo.xi && ./build/self_methods_demo
import "std/log.xi"
import "std/convert.xi"

interface Report { action run() }

class Sales implements Report {
    deps { logger: Logger }

    action run() {
        let header = banner("Q4")                 // sibling helper (not in the interface)
        logger.info(header)
        logger.info("5! = " + int_to_string(factorial(5)))   // recursive sibling call
        emit(1)                                    // overloaded sibling, routed by guard
        emit(42)
    }

    mapper banner(label: String) -> String => "== " + label + " report =="

    mapper factorial(n: Integer) -> Integer {
        if n <= 1 { return 1 }
        return n * factorial(n - 1)
    }

    action emit(n: Integer) where n >= 10 { logger.info("big: " + int_to_string(n)) }
    action emit(n: Integer)               { logger.info("small: " + int_to_string(n)) }
}

async entry (report: Report) main(args: String[]) {
    report.run()
}

module App {}
