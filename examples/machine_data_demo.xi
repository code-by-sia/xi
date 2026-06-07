// A stateful machine: named states + machine-wide `data`, with transitions that
// take parameters, are gated by `where` guards, and `update` the context. An
// illegal move (wrong source state OR a failed guard) signals IllegalTransition.
import "std/log.xi"
machine Lock {
    states  Locked, Open
    initial Locked
    terminal -
    data { code: String = "1234", attempts: Integer = 0 }

    unlock(attempt: String) : Locked -> Open
        where attempt == data.code
        update { attempts: 0 }

    fail(attempt: String) : Locked -> Locked
        where attempt != data.code
        update { attempts: data.attempts + 1 }

    lock : Open -> Locked
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let l = Lock.start()
    logger.print("start:      " + l.state + ", attempts=" + l.data.attempts)

    l = l.fail("0000")                 // guard holds -> stay Locked, attempts++
    l = l.fail("9999")
    logger.print("after fails: " + l.state + ", attempts=" + l.data.attempts)

    // `can` checks legality (source state + guard) without moving.
    logger.print("can unlock 0000? " + l.can(unlock, "0000"))
    logger.print("can unlock 1234? " + l.can(unlock, "1234"))

    try {
        l = l.unlock("0000")           // guard fails -> illegal
    } catch e: IllegalTransition {
        // an interrupt handler runs as an isolated frame: it sees globals, not
        // the entry's injected `logger`, so report via system.stdout here.
        system.stdout.writeln("illegal: " + e.from + " -> " + e.to)
        recover
    }

    l = l.unlock("1234")               // guard holds -> Open, attempts reset
    logger.print("final:      " + l.state + ", attempts=" + l.data.attempts)
    return 0
}
