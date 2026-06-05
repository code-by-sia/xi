// Interrupts: resumable conditions. A signalling function SUSPENDS at the
// signal site; an enclosing handler decides — recover (run the inline restart,
// continue) or skip (abandon the rest of the function).
interrupt Over { x: Integer }

producer calc(n: Integer) interrupts Over {
    if n > 100 {
        signal Over { x: n } recover {
            system.stdout.writeln("  recovered (was " + n + ")")
        }
    }
    system.stdout.writeln("  calc done with " + n)
}

// The signal can originate several frames below the handler.
consumer driver(n: Integer) interrupts Over {
    calc(n)
}

async entry main(args: String[]) -> Integer {
    system.stdout.writeln("recover (x <= 200):")
    try { driver(150) } catch e: Over {
        if e.x > 200 { skip } else { recover }
    }
    system.stdout.writeln("...continued")

    system.stdout.writeln("skip (x > 200):")
    try { driver(999) } catch e: Over {
        if e.x > 200 { skip } else { recover }
    }
    system.stdout.writeln("...continued (calc was abandoned)")

    system.stdout.writeln("no signal:")
    try { driver(5) } catch e: Over { recover }
    return 0
}
