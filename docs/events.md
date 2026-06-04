# Events (`listener` & `std/events`)

X has a built-in **publish/subscribe** event system. A producer publishes an
**event** — a topic and a [serializable](serialization.md) `Json` payload — and
any **`listener`** subscribed to that topic reacts. Producers and listeners never
reference each other; the bus connects them.

```x
import "std/json.x"
import "std/events.x"
```

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
