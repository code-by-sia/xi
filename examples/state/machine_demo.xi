// Machines — a finite state machine as an immutable value. A `machine` declares
// its `states`, the `initial` one, optional `terminal` states, and a set of
// named transitions (`name : From... -> To`). Calling a transition returns a new
// value in the target state; an illegal move signals the `IllegalTransition`
// interrupt so the caller can `recover` (stay put) or unwind.
import "std/log.xi"
machine Door {
    states  Closed, Open, Locked
    initial Closed
    terminal -
    open   : Closed       -> Open
    close  : Open         -> Closed
    lock   : Closed, Open -> Locked
    unlock : Locked       -> Closed
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let d = Door.start()
    logger.print("start  = " + d.state)

    d = d.open()
    logger.print("open   = " + d.state)

    d = d.lock()
    logger.print("lock   = " + d.state)

    // Locked has no `open` edge — the illegal move is resumable.
    try {
        d = d.open()
    } catch e: IllegalTransition {
        // an interrupt handler runs as an isolated frame: it sees globals, not
        // the entry's injected `logger`, so report via system.stdout here.
        system.stdout.writeln("illegal " + e.from + " -> " + e.to)
        recover
    }

    d = d.unlock()
    logger.print("final  = " + d.state)
    return 0
}
