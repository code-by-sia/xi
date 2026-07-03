// `capture` — bind the value of a sub-expression to a name (declared with its
// type) and keep using it after the statement. Useful when a call is buried in a
// larger expression but you also want its result later.
//
//   xc examples/capture_demo.xi && ./build/capture_demo
import "std/log.xi"

mapper foo(n: Integer) -> Integer { return n * 2 }
mapper bar(n: Integer) -> Integer { return n + 1 }

type Box = { v: Integer }
mapper    make(n: Integer) -> Box { return Box { v: n } }
predicate positive(b: Box)         { return b.v > 0 }

async entry (logger: Logger) main(args: String[]) -> Integer {
    // capture both call results inside a comparison, then use them afterwards
    let bigger = foo(10) capture a: Integer > bar(10) capture b: Integer
    logger.info("a=" + a + " b=" + b + " bigger=" + bigger)   // a=20 b=11 bigger=true

    // capture a struct mid-call and read a field from it later
    if positive(make(7) capture box: Box) {
        logger.info("box.v = " + box.v)                        // 7
    }
    return 0
}

module App {}
