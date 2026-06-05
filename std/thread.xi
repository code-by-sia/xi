// std/thread — share-nothing OS threads with channels.  import "std/thread.xi"
//
// Threads cannot share mutable state; they communicate only through channels
// (thread-safe FIFOs carrying string payloads, copied across the boundary). A
// `parallel` block spawns an OS thread and yields a Thread handle:
//
//     let jobs    = thread.channel()
//     let results = thread.channel()
//
//     let worker = parallel (jobs, results) {   // captures must be channels
//         while not thread.stopped() {          // cooperative stop flag
//             let job = jobs.recv()             // blocks until a value (or close)
//             results.send("done: " + job)
//         }
//     }
//
//     jobs.send("a")
//     let r = results.recv()
//     worker.stop()                             // request stop
//     jobs.close()                              // unblock a pending recv
//     worker.wait()                             // join
//
// Surface (compiler built-ins — no further declarations needed here):
//   thread.channel() -> Channel        thread.stopped() -> Bool
//   ch.send(s) / ch.recv() -> String / ch.close()
//   parallel [(caps...)] { ... } -> Thread
//   t.stop() / t.wait() / t.running() -> Bool
//
// `parallel`, `thread`, `Channel`, and `Thread` are reserved when this model is
// used. Payloads are strings today; use std/json to pass structured data.
