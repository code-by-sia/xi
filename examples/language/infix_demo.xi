// Infix functions — mark a two-argument function `infix` and it can be called
// as `a f b` (sugar for `f(a, b)`). It's still an ordinary function, so the
// `f(a, b)` form keeps working too.
//
//   xc examples/infix_demo.xi && ./build/infix_demo
import "std/log.xi"
import "std/convert.xi"

infix mapper    plus(a: Integer, b: Integer) -> Integer { return a + b }
infix mapper    max(a: Integer, b: Integer) -> Integer  { if a > b { return a } return b }
infix predicate divides(a: Integer, b: Integer)         { return b % a == 0 }

// Reads like a small DSL:
type Money = { cents: Integer }
infix creator usd(dollars: Integer, cents: Integer) -> Money { return Money { cents: dollars * 100 + cents } }

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.info("5 plus 3        = " + (5 plus 3))            // 8
    logger.info("2 plus 3 plus 4 = " + (2 plus 3 plus 4))     // 9  (left-associative)
    logger.info("plus(10, 20)    = " + plus(10, 20))          // 30 (normal call still works)
    logger.info("7 max 4         = " + (7 max 4))             // 7

    if 3 divides 12 { logger.info("3 divides 12") }           // infix predicate in a guard

    let price = 19 usd 99
    logger.info("price cents     = " + int_to_string(price.cents))   // 1999
    return 0
}

module App {}
