// Async event delivery — `Events.runAsync()` drains the event queue on a worker
// thread and dispatches to listeners off the publishing thread. `Events.stop()`
// closes the queue so the pump exits; join it with the returned Thread handle.
//
//   xc examples/async_events_demo.xi && ./build/async_events_demo
import "std/time.xi"
import "std/events.xi"
import "std/convert.xi"
import "std/thread.xi"
import "std/log.xi"

event Job { id: Integer }

interface Emitter { producer fire(n: Integer) }
class Producer implements Emitter {
    deps { events: PublisherService }
    producer fire(n: Integer) { events.publish("jobs", Job { id: n }) }
}

class Worker {
    deps { logger: Logger }
    listener onJob(e: Job) on "jobs" {
        logger.print("handled job " + int_to_string(e.id))
    }
}

module App {}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let pump = Events.runAsync()        // deliver on a background thread
    let q = App.resolve(Emitter)
    let i = 0
    while i < 5 { q.fire(i) i = i + 1 }  // publish from the main thread

    time.sleepMs(200)                   // let the worker drain the queue
    Events.stop()                       // close the queue -> the pump returns
    pump.wait()                         // join the worker
    logger.print("done")
    return 0
}
