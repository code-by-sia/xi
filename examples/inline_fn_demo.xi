// Inline function bodies: `=> expr` is sugar for `{ return expr }`. Works for any
// function kind, for methods, and for `where`-overloads.
//
//   xc examples/inline_fn_demo.xi && ./build/inline_fn_demo
import "std/log.xi"
import "std/convert.xi"

mapper    square(n: Integer) -> Integer => n * n
predicate isEven(n: Integer)            => n % 2 == 0
mapper    greet(name: String) -> String => "Hi, " + name + "!"

// where-overloads, inline
mapper tier(n: Integer) -> String where n >= 100 => "high"
mapper tier(n: Integer) -> String                => "low"

interface Calc { mapper apply(n: Integer) -> Integer }
class Doubler implements Calc {
    deps {}
    mapper apply(n: Integer) -> Integer => n * 2     // inline method
}

// Regression: inline `=>` method with the class's closing brace on the SAME
// line. The body collector must stop at that depth-0 `}` instead of swallowing
// it (which used to emit a stray `};` and break C compilation).
interface Tripler { mapper apply(n: Integer) -> Integer }
class Tri implements Tripler { deps {} mapper apply(n: Integer) -> Integer => n * 3 }

async entry (logger: Logger) main(args: String[]) {
    logger.print(int_to_string(square(7)))     // 49
    if isEven(4) { logger.print("4 is even") }
    logger.print(greet("John Doe"))                 // Hi, John Doe!
    logger.print(tier(500) + " / " + tier(5))  // high / low
    logger.print(int_to_string(App.resolve(Calc).apply(21)))  // 42
    logger.print(int_to_string(App.resolve(Tripler).apply(14)))  // 42
}

module App {}
