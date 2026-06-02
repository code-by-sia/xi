// Hello, world in X

interface Printer {
    consumer print(msg: String)
}

class ConsolePrinter implements Printer {
    deps {}

    consumer print(msg: String) {
        system.stdout.writeln(msg)
    }
}

module HelloApp {
    bind Printer -> ConsolePrinter as singleton
}

async entry main(args: String[]) -> Integer {
    let printer = HelloApp.resolve(Printer)
    printer.print("Hello, World!")
    return 0
}
