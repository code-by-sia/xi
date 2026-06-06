// `match` — block arms, inline-expression arms (sugar for `{ return expr }`),
// multi-key selectors, and an `else` default.
//
//   xc examples/match_demo.xi && ./build/match_demo
import "std/convert.xi"

mapper classify(code: String) -> Integer {
    match code {
        "x"                -> { return 345 }   // block arm
        "A"                -> 101              // inline: same as -> { return 101 }
        ("BA", "BD", "BR") -> 200             // multi-key: matches any listed key
        else               -> 300             // default (alias for `_`)
    }
}

// Works for integers too; a bare identifier arm binds the subject.
mapper bucket(n: Integer) -> String {
    match n {
        (1, 2, 3) -> "low"
        (4, 5)    -> "mid"
        n         -> "other:" + int_to_string(n)
    }
}

async entry main(args: String[]) -> Integer {
    system.stdout.writeln(int_to_string(classify("x")))    // 345
    system.stdout.writeln(int_to_string(classify("A")))    // 101
    system.stdout.writeln(int_to_string(classify("BD")))   // 200
    system.stdout.writeln(int_to_string(classify("zzz")))  // 300
    system.stdout.writeln(bucket(2))                        // low
    system.stdout.writeln(bucket(5))                        // mid
    system.stdout.writeln(bucket(9))                        // other:9
    return 0
}

module App {}
