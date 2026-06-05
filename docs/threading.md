# Threading (`parallel` & `std/thread`)

Xi threads are **share-nothing**: a thread can't reach another thread's mutable
state. They communicate only through **channels** — thread-safe FIFOs that carry
copied string payloads. A `parallel` block runs on a new OS thread and yields a
`Thread` handle you can stop, join, and poll.

```x
import "std/thread.xi"
```

## Channels

`thread.channel()` makes a channel. `send` enqueues a copy; `recv` blocks until a
value arrives (or the channel is closed, in which case it returns `""`); `close`
wakes any blocked `recv`.

```x
let ch = thread.channel()
ch.send("hello")
let msg = ch.recv()      // "hello"
ch.close()
```

Payloads are strings today — use [`std/json`](serialization.md) to pass
structured data across the boundary.

## `parallel` blocks

`parallel [(captures…)] { body }` spawns a thread running `body` and evaluates to
a `Thread`. The only things a block may capture are **channels**, listed
explicitly — they are the share-nothing boundary, passed by value:

```x
let jobs    = thread.channel()
let results = thread.channel()

let worker = parallel (jobs, results) {
    while not thread.stopped() {      // cooperative stop flag
        let job = jobs.recv()
        if job == "" { return 0 }     // channel closed -> exit
        results.send("done: " + job)
    }
    return 0
}
```

| Operation | Meaning |
|-----------|---------|
| `thread.stopped()` | inside a block — has `.stop()` been requested? |
| `t.stop()` | request cooperative stop (sets the flag) |
| `t.wait()` | join — block until the thread finishes |
| `t.running()` | `false` once the thread's body has returned |

## Shutting down

`stop()` only sets a flag; a thread blocked in `recv()` won't see it until it
wakes. The idiom is **stop, then close the channels it waits on, then wait**:

```x
worker.stop()
jobs.close()     // unblocks the pending recv -> body returns
worker.wait()
```

See `examples/thread_demo.xi` for a two-worker producer/consumer.

## Notes & limits

- Channels carry **strings**; serialize structured data with `std/json`.
- Captures must be channels (the only legal cross-thread references). Other state
  stays thread-local — that's what makes the model share-nothing.
- `parallel`, `thread`, `Channel`, and `Thread` are reserved when threading is used.
- Channels are unbounded FIFOs (no backpressure yet) and unbuffered selection /
  timeouts aren't available yet.
