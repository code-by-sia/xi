import "std/math.x"
import "std/text.x"
import "std/convert.x"

async entry main(args: String[]) -> Integer {
    system.stdout.writeln("sqrt(2)   = " + math.sqrt(2.0))
    system.stdout.writeln("max(3,7)  = " + math.max(3, 7))
    system.stdout.writeln("upper     = " + text.toUpper("hello"))
    system.stdout.writeln("trim      = [" + text.trim("   hi   ") + "]")
    system.stdout.writeln("repeat    = " + text.repeat("ab", 3))
    system.stdout.writeln("indexOf   = " + text.indexOf("hello world", "world"))

    let r = convert.parseInteger("42")
    if isOk(r) { system.stdout.writeln("parsed    = " + r.value) }
    let bad = convert.parseInteger("oops")
    if isErr(bad) { system.stdout.writeln("error     = " + bad.err) }
    return 0
}
