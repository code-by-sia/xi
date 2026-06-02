// Entry point that imports two namespaced modules from separate files.
import "math.x"
import "text.x"

async entry main(args: String[]) -> Integer {
    system.stdout.writeln(text.shout("hello multi-file"))
    system.stdout.writeln("2 + 3 = " + math.add(2, 3))
    system.stdout.writeln("4^2 = "  + math.square(4))
    return 0
}
