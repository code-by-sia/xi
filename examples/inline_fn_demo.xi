// Inline function bodies: `=> expr` is sugar for `{ return expr }`. Works for any
// function kind, for methods, and for `where`-overloads.
//
//   xc examples/inline_fn_demo.xi && ./build/inline_fn_demo
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

async entry main(args: String[]) -> Integer {
    system.stdout.writeln(int_to_string(square(7)))     // 49
    if isEven(4) { system.stdout.writeln("4 is even") }
    system.stdout.writeln(greet("Ada"))                 // Hi, Ada!
    system.stdout.writeln(tier(500) + " / " + tier(5))  // high / low
    system.stdout.writeln(int_to_string(App.resolve(Calc).apply(21)))  // 42
    return 0
}

module App {}
