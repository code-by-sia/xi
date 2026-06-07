// Interrupts: resumable conditions. A signalling function SUSPENDS at the
// signal site; an enclosing handler decides — recover (run the inline restart,
// continue) or skip (abandon the rest of the function).
import "std/log.xi"

interrupt Over { x: Integer }

producer calc(n: Integer, logger: Logger) interrupts Over {
    if n > 100 {
        signal Over { x: n } recover {
            logger.print("  recovered (was " + n + ")")
        }
    }
    logger.print("  calc done with " + n)
}

// The signal can originate several frames below the handler.
consumer driver(n: Integer, logger: Logger) interrupts Over {
    calc(n, logger)
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.print("recover (x <= 200):")
    try { driver(150, logger) } catch e: Over {
        if e.x > 200 { skip } else { recover }
    }
    logger.print("...continued")

    logger.print("skip (x > 200):")
    try { driver(999, logger) } catch e: Over {
        if e.x > 200 { skip } else { recover }
    }
    logger.print("...continued (calc was abandoned)")

    logger.print("no signal:")
    try { driver(5, logger) } catch e: Over { recover }
    return 0
}
