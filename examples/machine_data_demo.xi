// A stateful machine: named states + machine-wide `data`, with transitions that
// take parameters, are gated by `where` guards, and `update` the context. An
// illegal move (wrong source state OR a failed guard) signals IllegalTransition.
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

async entry main(args: String[]) -> Integer {
    let l = Lock.start()
    system.stdout.writeln("start:      " + l.state + ", attempts=" + l.data.attempts)

    l = l.fail("0000")                 // guard holds -> stay Locked, attempts++
    l = l.fail("9999")
    system.stdout.writeln("after fails: " + l.state + ", attempts=" + l.data.attempts)

    // `can` checks legality (source state + guard) without moving.
    system.stdout.writeln("can unlock 0000? " + l.can(unlock, "0000"))
    system.stdout.writeln("can unlock 1234? " + l.can(unlock, "1234"))

    try {
        l = l.unlock("0000")           // guard fails -> illegal
    } catch e: IllegalTransition {
        system.stdout.writeln("illegal: " + e.from + " -> " + e.to)
        recover
    }

    l = l.unlock("1234")               // guard holds -> Open, attempts reset
    system.stdout.writeln("final:      " + l.state + ", attempts=" + l.data.attempts)
    return 0
}
