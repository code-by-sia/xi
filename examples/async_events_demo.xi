// Async event delivery — `Events.runAsync()` drains the event queue on a worker
// thread and dispatches to listeners off the publishing thread. `Events.stop()`
// closes the queue so the pump exits; join it with the returned Thread handle.
//
//   xc examples/async_events_demo.xi && ./build/async_events_demo
import "std/time.xi"
import "std/events.xi"
import "std/convert.xi"
import "std/thread.xi"

event Job { id: Integer }

interface Queue { producer fire(n: Integer) }
class Producer implements Queue {
    deps { events: PublisherService }
    producer fire(n: Integer) { events.publish("jobs", Job { id: n }) }
}

class Worker {
    deps {}
    listener onJob(e: Job) on "jobs" {
        system.stdout.writeln("handled job " + int_to_string(e.id))
    }
}

module App {}

async entry main(args: String[]) -> Integer {
    let pump = Events.runAsync()        // deliver on a background thread
    let q = App.resolve(Queue)
    let i = 0
    while i < 5 { q.fire(i) i = i + 1 }  // publish from the main thread

    time.sleepMs(200)                   // let the worker drain the queue
    Events.stop()                       // close the queue -> the pump returns
    pump.wait()                         // join the worker
    system.stdout.writeln("done")
    return 0
}
