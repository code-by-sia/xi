// First-class closures: a lambda `(p: T) => expr` is a value of function type
// `(T) -> U`. Bind it, call it, and pass it to higher-order functions.
//
//   xc examples/closures_demo.xi && ./build/closures_demo
//
// v1 scope: one parameter, typed; capture-free (the body sees only its own
// parameter); the body's result type must match the declared `-> U`.
import "std/log.xi"
import "std/convert.xi"

// Higher-order: take a function value and apply it.
producer apply(f: (Integer) -> Integer, x: Integer) -> Integer { return f(x) }
producer twice(f: (Integer) -> Integer, x: Integer) -> Integer { return f(f(x)) }
producer keep(xs: Integer[], p: (Integer) -> Bool) -> Integer {
    let n = 0
    for x in xs { if p(x) { n = n + 1 } }
    return n
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    // a lambda bound to a local, then called
    let inc = (n: Integer) => n + 1
    logger.info("inc(41) = " + int_to_string(inc(41)))

    // passed to higher-order functions
    logger.info("apply +1 to 5  = " + int_to_string(apply((n: Integer) => n + 1, 5)))
    logger.info("twice doubling = " + int_to_string(twice((n: Integer) => n + n, 3)))   // 3->6->12

    // a predicate value
    let big = (n: Integer) => n > 3
    logger.info("how many > 3   = " + int_to_string(keep([1, 5, 2, 9, 4], big)))         // 3
    return 0
}

module ClosuresDemo {}
