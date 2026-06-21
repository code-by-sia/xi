// scheduled … cron "<expr>" { … } — run a block on a cron schedule.
//
// A `scheduled` job declares its own dependencies (auto-wired, like a function)
// and a 5-field cron expression: "minute hour day-of-month month day-of-week".
// Declaring any scheduled job makes the program run a scheduler that keeps the
// process alive and fires each job when local time matches its cron.
//
//   xc examples/scheduled_demo.xi && ./build/scheduled_demo   # runs until Ctrl-C
import "std/log.xi"
import "std/convert.xi"

// every minute
scheduled (logger: Logger) heartbeat() cron "* * * * *" {
    logger.info("heartbeat")
}

// 04:05 every day  (minute=5 hour=4)
scheduled (logger: Logger) dailyReport() cron "5 4 * * *" {
    logger.info("running the daily report…")
}

// top of every hour  (minute=0)
scheduled (logger: Logger) hourly() cron "0 * * * *" {
    logger.info("hourly tick")
}

module App {}
