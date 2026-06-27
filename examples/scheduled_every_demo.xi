// Fixed-interval scheduled jobs: `every <N>ms` fires every N milliseconds
// (sub-second is honored, unlike cron's minute resolution). Mix with `cron`.
//
//   xc examples/scheduled_every_demo.xi && ./build/scheduled_every_demo
//
// Runs a scheduler that keeps the process alive (Ctrl-C to stop).
import "std/log.xi"

scheduled (logger: Logger) fastPoll() every 500ms {
    logger.info("poll (every 500ms)")
}

scheduled (logger: Logger) slowBeat() every 2000ms {
    logger.info("beat (every 2s)")
}

scheduled (logger: Logger) topOfMinute() cron "* * * * *" {
    logger.info("minute tick (cron)")
}

async entry main(args: String[]) -> Integer {
}

module App {}
