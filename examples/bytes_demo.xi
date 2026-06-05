// Bytes: a raw byte buffer type, distinct from String.
import "std/bytes.xi"

async entry main(args: String[]) -> Integer {
    let b = bytes.fromString("hello")
    system.stdout.writeln("length    = " + bytes.length(b))
    system.stdout.writeln("first byte= " + bytes.at(b, 0))      // 'h' = 104

    let full = bytes.concat(b, bytes.fromString(" world"))
    system.stdout.writeln("concat    = " + bytes.toString(full))
    system.stdout.writeln("slice 0:5 = " + bytes.toString(bytes.slice(full, 0, 5)))
    system.stdout.writeln("empty?    = " + bytes.isEmpty(bytes.empty()))
    return 0
}
