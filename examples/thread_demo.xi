// std/thread — share-nothing threads + channels. A `parallel` block runs on a
// new OS thread and yields a handle (stop/wait/running). Threads talk only over
// channels (thread-safe FIFOs of strings, copied across the boundary).
//
//   xc examples/thread_demo.xi && ./build/thread_demo
import "std/thread.xi"

async entry main(args: String[]) -> Integer {
    let jobs    = thread.channel()
    let results = thread.channel()

    // Spawn two workers competing on the same job channel. Captures (the
    // channels) are the only shared state — everything else is thread-local.
    let w1 = parallel (jobs, results) {
        while not thread.stopped() {
            let job = jobs.recv()              // blocks until a value (or close)
            if job == "" { return 0 }          // empty == channel closed
            results.send("w1 did " + job)
        }
        return 0
    }
    let w2 = parallel (jobs, results) {
        while not thread.stopped() {
            let job = jobs.recv()
            if job == "" { return 0 }
            results.send("w2 did " + job)
        }
        return 0
    }

    // Feed work; collect the answers.
    let i = 0
    while i < 5 { jobs.send(int_to_string(i)) i = i + 1 }
    let got = 0
    while got < 5 { system.stdout.writeln(results.recv()) got = got + 1 }

    // Cooperative shutdown: ask them to stop, then unblock their recv with a
    // close, then join.
    w1.stop()
    w2.stop()
    jobs.close()
    w1.wait()
    w2.wait()

    if w1.running() { system.stdout.writeln("w1 still running?!") } else { system.stdout.writeln("all workers joined") }
    return 0
}

module App {}
