// Machines — a finite state machine as an immutable value. A `machine` declares
// its `states`, the `initial` one, optional `terminal` states, and a set of
// named transitions (`name : From... -> To`). Calling a transition returns a new
// value in the target state; an illegal move signals the `IllegalTransition`
// interrupt so the caller can `recover` (stay put) or unwind.
machine Door {
    states  Closed, Open, Locked
    initial Closed
    terminal -
    open   : Closed       -> Open
    close  : Open         -> Closed
    lock   : Closed, Open -> Locked
    unlock : Locked       -> Closed
}

async entry main(args: String[]) -> Integer {
    let d = Door.start()
    system.stdout.writeln("start  = " + d.state)

    d = d.open()
    system.stdout.writeln("open   = " + d.state)

    d = d.lock()
    system.stdout.writeln("lock   = " + d.state)

    // Locked has no `open` edge — the illegal move is resumable.
    try {
        d = d.open()
    } catch e: IllegalTransition {
        system.stdout.writeln("illegal " + e.from + " -> " + e.to)
        recover
    }

    d = d.unlock()
    system.stdout.writeln("final  = " + d.state)
    return 0
}
