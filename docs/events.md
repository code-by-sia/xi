# Events (`listener` & `std/events`)

X has a built-in **publish/subscribe** event system with two tiers:

- **Typed application events** — declare `event T { … }` and `Events.emit(value)`
  dispatches the value **directly** to typed `listener (e: T)` methods,
  in-process, with **no serialization**. Use this for events that stay in the
  process.
- **String-topic events** — a producer publishes a `Json` payload under a string
  topic via an injected `PublisherService`; `listener (e: Event) on "topic"`
  methods receive them. Use this for dynamic/loosely-typed events.

Either way, an event leaving the process is serialized **only at the boundary**
through a replaceable transport. Producers and listeners never reference each
other; the bus connects them.

```x
import "std/json.x"
import "std/events.x"
```

## Typed application events (no serialization)

Declare a typed event and emit the domain value you already hold — no `Json`
building, and the field access in the listener is compile-checked:

```x
event OrderPaid { id: String, item: String, total: Number }

class Shop {
    deps {}
    producer checkout(item: String, total: Number) {
        Events.emit(OrderPaid { id: "o1", item: item, total: total })   // typed, direct
    }
}

class Receipts {
    deps { mailer: Mailer }                 // a listener gets its own deps wired
    listener onPaid(e: OrderPaid) {         // the parameter TYPE is the subscription
        mailer.send("buyer@x.dev", "Paid " + e.total + " for " + e.item)
    }
}
```

`Events` is built into the language — you do not inject or import it. `emit`
dispatches to every typed listener of that event type, in declaration order, on
the caller's thread. Nothing is serialized.

### Going external

Binding a non-default `PublisherService` makes `Events.emit` *also* serialize the
event (via a compiler-derived codec) and publish it on the wire — serialization
happens **only here, at the boundary**. Inbound, a transport hands received
messages to `Events.deliver(topic, json)`, which deserializes and dispatches to
the same typed listeners (without re-publishing):

```x
class WireBus implements PublisherService {          // outbound transport
    deps {}
    producer publish(topic: String, payload: Json) {
        net.sendText(conn, topic + "\t" + json.stringify(payload) + "\n")
    }
}

// inbound pump (a ConsumerService) reads the wire and re-injects typed events:
Events.deliver("OrderPaid", json.parse(body))        // fromJson -> typed dispatch

module App { bind PublisherService -> WireBus as singleton }   // producers unchanged
```

The event's canonical wire **topic** is its type name (`"OrderPaid"`). The
derived codec supports `String`, `Number`, `Integer`, `Bool`, `Json`, and nested
`event` fields (arrays are not encoded yet).

> The rest of this page covers the **string-topic** tier. The typed and
> string-topic tiers coexist; see the [design notes](proposals/typed-events.md).

## Publishing

Depend on the injected **`PublisherService`** and call `publish(topic, payload)`:

```x
class Shop {
    deps { bus: PublisherService }

    producer checkout(item: String, total: Number) {
        let p = json.object()
        p = json.set(p, "item", json.str(item))
        p = json.set(p, "total", json.num(total))
        bus.publish("order.paid", p)
    }
}
```

A topic is a dotted string (`"order.paid"`). The payload is any `Json` value.

## Reacting — the `listener` kind

`listener` is a [function kind](language-guide.md): a `consumer` the runtime calls
when a matching event is published. It names its topic with `on "…"` and receives
an `Event`:

```x
class Receipts {
    deps { mailer: Mailer }            // listeners may declare their own deps

    listener email(e: Event) on "order.paid" {
        let item  = json.getString(e.payload, "item")
        let total = json.getNumber(e.payload, "total")
        mailer.send("buyer@x.dev", "Paid " + total + " for " + item)
    }
}
```

- **`Event`** is `{ topic: String, payload: Json }`.
- **`on "topic"`** declares the subscription. A pattern ending in `.*` matches by
  prefix — `"order.*"` catches `order.paid`, `order.refunded`, … :

```x
class Audit {
    deps {}
    listener log(e: Event) on "order.*" {
        system.stdout.writeln("[audit] " + e.topic + " " + json.stringify(e.payload))
    }
}
```

- Listeners are **auto-discovered**. Declaring one registers it — there is no
  manual `subscribe` call. Each delivery resolves a fresh owning instance through
  DI (so the listener's own `deps` are wired).

## Putting it together

```x
async entry main(args: String[]) -> Integer {
    let shop = App.resolve(Store)      // Store is Shop's interface
    shop.checkout("book", 29.0)        // Receipts.email AND Audit.log both fire
    return 0
}

module App {}                          // default LocalBus; bind to swap
```

```
mail to buyer@x.dev: Paid 29 for book
[audit] order.paid {"item":"book","total":29}
```

## Delivery semantics

- **Synchronous, in-process, in registration order**, on the publishing thread —
  `publish` returns only after every matching listener has run.
- A topic may have any number of listeners (including zero).
- Matching is exact, or `prefix.*`.

## Swapping the transport

`PublisherService` is an ordinary interface with a default implementation
(`LocalBus`, which dispatches in-process). Bind a different one in your app module
to change transport — producers and listeners are untouched. Serialization is the
bridge: an out-of-process bus `stringify`s the payload on publish and `parse`s it
on the far side.

```x
class KafkaBus implements PublisherService {
    deps { conn: net.Conn }
    producer publish(topic: String, payload: Json) {
        net.sendText(conn, topic + "\t" + json.stringify(payload) + "\n")
    }
}

module App {
    bind PublisherService -> KafkaBus as singleton
}
```

## Lowering

Each `listener` compiles to its method plus a generated trampoline that builds the
`Event` and invokes the method on a DI-resolved instance. At startup
`xc_events_init()` registers every trampoline with the runtime registry; `publish`
walks the registry and calls the matching handlers. No machinery beyond a string
compare and a function-pointer call.

## Notes & limits

- **Typed payloads** (`listener f(e: OrderPaid)`) await compile-time reflection;
  today the payload is `Json` and you read fields explicitly.
- Async/buffered delivery, retries, and a swappable consumer-side service are
  [proposed](proposals/event-system.md) but not yet implemented — delivery is the
  synchronous `LocalBus`.

See `examples/event_demo.x`.
