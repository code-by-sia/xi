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

Channels carry **any data**, not just strings:

- a `String` passes through as-is;
- a structured value — an `event` or compound `type` — is JSON-serialized on
  `send` and rebuilt with the typed `recv(T)`;
- numbers and bools are stringified automatically.

```x
type Order = { id: Integer, item: String, qty: Integer }

ch.send(Order { id: 1, item: "book", qty: 2 })   // serialized
let o = ch.recv(Order)                           // rebuilt as an Order
```

`recv()` with no argument returns the raw `String`; `recv(T)` deserializes a `T`.
Serialization uses the same derived codecs as `std/web` / `std/events`.

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

## Memory

Because threads are share-nothing, each thread allocates its values from its own
**arena**, and the whole arena is freed when the thread finishes (or is stopped
and returns). So a thread reclaims everything it allocated on exit — there's no
cross-thread garbage, and the main thread is unaffected (it keeps the usual
allocate-and-free-at-exit behaviour). Data sent over a channel is copied, so it
survives the sender's cleanup. (This is the per-thread slice of the
[memory-management plan](proposals/memory-management.md); note the arena is freed
at thread *exit*, not per loop iteration.)

## Notes & limits

- Channels carry strings and structured values (`send(dto)` / `recv(T)`, via
  derived JSON codecs); the wire format is a copied string.
- Captures must be channels (the only legal cross-thread references). Other state
  stays thread-local — that's what makes the model share-nothing.
- `parallel`, `thread`, `Channel`, and `Thread` are reserved when threading is used.
- Channels are unbounded FIFOs (no backpressure yet) and unbuffered selection /
  timeouts aren't available yet.
