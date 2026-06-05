# Events (`listener` & `std/events`)

Xi has a built-in **typed publish/subscribe** event system. A producer publishes
any **DTO** under a topic; a **`listener`** subscribed to that topic receives the
**typed value** — never `Json`. Producers and listeners never reference each
other, and the *same* code works whether events stay in the process or cross the
network — only the bound transport changes.

```x
import "std/json.xi"
import "std/events.xi"
```

## Declaring an event

An **`event`** is a DTO — an ordinary value type that may be published. (The
compiler also derives a JSON codec for it, used *only* by external transports.)

```x
event OrderPaid { id: String, item: String, total: Number }
```

## Publishing — any DTO under a topic

A producer depends on the injected **`PublisherService`** and calls
`publish(topic, dto)`:

```x
class Shop {
    deps { events: PublisherService }
    producer checkout(item: String, total: Number) {
        events.publish("order.paid", OrderPaid { id: "o1", item: item, total: total })
    }
}
```

No `Json` is built. The DTO is the payload.

## Reacting — typed listeners

A **`listener`** names its topic with `on "…"` and receives the **typed DTO**:

```x
class Receipts {
    deps { mailer: Mailer }                       // listeners get their own deps wired
    listener onPaid(e: OrderPaid) on "order.paid" {
        mailer.send("buyer@x.dev", "Paid " + e.total + " for " + e.item)
    }
}
```

A topic may have any number of listeners; all fire (in declaration order). Each
delivery resolves a fresh owning instance through DI.

## Delivery is queued; run the pump

The default transport puts published events on an in-memory queue. Deliver them
by running the **pump** — the bound `ConsumerService`:

```x
async entry main(args: String[]) -> Integer {
    let shop = App.resolve(Store)
    shop.checkout("book", 29.0)
    Events.run()                 // drain the queue -> listeners (no serialization)
    return 0
}
module App {}                    // MemoryBus / MemoryConsumer are the defaults
```

`Events.run()` resolves the `ConsumerService` and runs it; the default
`MemoryConsumer` drains the in-memory queue and dispatches each event to its
typed listeners. Nothing is serialized — the typed value is passed straight
through.

### Async delivery — `Events.runAsync()`

`Events.run()` drains on the calling thread. `Events.runAsync()` instead spawns a
background worker (a [thread](threading.md)) that blocks on the queue and
dispatches events as they arrive, decoupling delivery from publishing. It returns
a `Thread` handle; `Events.stop()` closes the queue so the worker exits, then
`wait()` joins it.

```x
async entry main(args: String[]) -> Integer {
    let pump = Events.runAsync()     // deliver on a background thread
    let shop = App.resolve(Store)
    shop.checkout("book", 29.0)      // publish from this thread

    Events.stop()                    // close the queue -> the pump returns
    pump.wait()                      // join the worker
    return 0
}
```

Listeners then run on the worker thread, so treat their work as you would any
threaded code. See `examples/async_events_demo.xi`.

## Application vs. external: only the transport differs

The producer and the listeners above never change. The **only** difference
between an in-process event and one that crosses the network is which
`PublisherService` / `ConsumerService` is bound:

| | Application (default) | External (your impl) |
|---|---|---|
| `PublisherService` | `MemoryBus` — enqueue, no serialize | serialize + send on the wire |
| `ConsumerService` | `MemoryConsumer` — drain queue | receive + deserialize + dispatch |
| Payload in transit | the **typed value** (a pointer) | bytes (your format) |

An event travels internally as a **type-erased envelope** (topic + type name +
an opaque pointer to the typed value). Producers and listeners only ever see the
topic and the typed DTO — the envelope is what the transport carries.

### Writing an external transport

The system gives transports five helpers over the envelope:

| Helper | Purpose |
|--------|---------|
| `Events.topic(e)` / `Events.type(e)` | the event's topic / DTO type name |
| `Events.encode(e) -> Json` | serialize the payload (by type) |
| `Events.decode(topic, type, json) -> Event` | rebuild a typed envelope |
| `Events.dispatch(e)` | deliver an envelope to its typed listeners |

```x
// Outbound: serialize and ship. JSON appears ONLY here.
class WireBus implements PublisherService {
    deps { conn: net.Conn }
    producer publish(e: Event) {
        net.sendText(conn, Events.topic(e) + "\t" + Events.type(e)
                         + "\t" + json.stringify(Events.encode(e)) + "\n")
    }
}

// Inbound: receive, rebuild the typed event, dispatch.
class WireConsumer implements ConsumerService {
    deps { conn: net.Conn }
    consumer run() {
        let line = net.recvText(conn, 65536)
        // … split into topic / type / body …
        Events.dispatch(Events.decode(topic, type, json.parse(body)))
    }
}

module App {
    bind PublisherService -> WireBus      as singleton
    bind ConsumerService  -> WireConsumer as singleton
}
```

The derived codec supports `String`, `Number`, `Integer`, `Bool`, `Json`, nested
`event` fields, and **arrays** of those (`String[]`, `Order[]`, …) — each encoded
element by element. (Arrays of *primitive numbers/bools* in a payload await the
language's general primitive-array-in-struct support; `String[]` and arrays of
`event` types work today.)

## Lowering

`events.publish(topic, dto)` wraps the DTO into an envelope (`xc_wrap_T` heap-copies
the value — no serialization) and hands it to the bound `PublisherService`.
`Events.dispatch` is a generated topic/type switch that casts the payload back to
the listener's type and calls it. `encode`/`decode` are generated switches over
the derived `toJson`/`fromJson`. Nothing is serialized unless a transport calls
`encode`/`decode`.

## Notes & limits

- `Events.run()` delivers **synchronously** on the calling thread;
  `Events.runAsync()` delivers on a background worker thread (the queue is
  thread-safe). Either way, run the pump to drain the queue.
- A listener receives the DTO only (not the topic string).
- The codec encodes `String[]` and arrays of `event` types; arrays of primitive
  numbers/bools await general primitive-array-in-struct support.

See `examples/typed_event_demo.xi`.
