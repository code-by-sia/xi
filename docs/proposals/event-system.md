# Proposal: Event system — publish/subscribe with `listener`

> **Status: Draft — design for review.** Builds on the **shipped**
> [serialization library](../serialization.md) (`std/json`) and the
> [dependency-injection](../language-guide.md) system. Not yet implemented.

## Why

X has first-class dependency injection but no first-class way for one part of a
program to **announce that something happened** and let unrelated parts react.
Today you wire that by hand: pass callbacks, or have services call each other
directly — which couples the producer of a fact to every consumer of it.

This proposal adds a **publish/subscribe event system** as a language + library
feature:

- A **producer** publishes an **event** — a topic plus a **serializable payload**.
- A new function kind, **`listener`**, declares a reaction to a topic. Listeners
  are discovered and registered automatically, exactly like DI implementations.
- Two replaceable services — **`PublisherService`** and **`ConsumerService`** —
  carry events from producers to listeners. Both have a **default in-process
  implementation**; an app can `bind` a different one (Kafka, NATS, an in-memory
  test double) in its module without touching producer or listener code.

The payload is a [`Json`](../serialization.md) value, so an event is serializable
by construction — the same bytes can stay in-process or cross a network.

## The shape of an event

An **event** is a topic (a dotted string) and a `Json` payload:

```x
type Event = {
    topic:   String,   // "user.created", "order.paid", …
    payload: Json,     // serializable; built with std/json
    id:      String,   // unique per emission (for dedup / tracing)
    at:      Integer,  // emit time (epoch nanos)
}
```

Producers usually don't fill `id`/`at` themselves — `publish` stamps them.

## Publishing — the producer side

A `producer` builds a payload and hands it to the injected `PublisherService`:

```x
import "std/json.x"

class SignupFlow {
    deps { events: PublisherService }

    producer register(name: String, email: String) {
        // … create the user …
        let p = json.object()
        p = json.set(p, "name", json.str(name))
        p = json.set(p, "email", json.str(email))
        events.publish("user.created", p)     // fire and forget
    }
}
```

`publish(topic, payload)` returns nothing to the caller about who handled it —
that decoupling is the point. (`PublisherService` is the natural collaborator of
the `producer` kind: a producer is the effectful "makes something happen"
function, and an event is how that fact leaves the producer.)

## Reacting — the `listener` kind

`listener` is the eighth [function kind](../language-guide.md). A listener names
the topic it reacts to and receives the `Event`:

```x
class Welcome {
    deps { mailer: Mailer }

    listener greet(e: Event) on "user.created" {
        let name = json.getString(e.payload, "name")
        mailer.send(json.getString(e.payload, "email"), "Welcome, " + name + "!")
    }
}
```

- **`on "topic"`** declares the subscription. A topic may end in `.*` to match a
  prefix (`"order.*"` catches `order.paid`, `order.refunded`, …).
- A listener is a **`consumer` with a subscription**: it has effects, returns
  nothing, and may declare its own `deps`. Like every kind it can satisfy an
  interface method.
- Listeners are **auto-discovered** the way DI implementations are — declaring one
  registers it; no manual `subscribe` call. (An app can still opt a listener out
  with a `where` guard, future.)

Semantically a `listener` is "a `consumer` the runtime calls for you when a
matching event is published," so it reuses the consumer rules (effects allowed,
no return value).

### Lexer / kind wiring

Add `listener` as kind `220` alongside the existing kinds (`creator`…`reducer`,
`entry`). Parsing reuses the consumer path plus an `on <string-literal>` clause
captured on the function's spec.

## The two services

Producers depend on **`PublisherService`**; the runtime delivery side is
**`ConsumerService`**. Both are ordinary X interfaces, so both are **replaceable
through DI**:

```x
interface PublisherService {
    producer publish(topic: String, payload: Json)
}

interface ConsumerService {
    // Wires up discovered listeners and routes an event to the matching ones.
    consumer register(topic: String, handler: Listener)
    consumer deliver(e: Event)
}
```

### Default implementation (in-process, synchronous)

The library ships a default that needs no configuration:

- **`LocalBus`** implements *both* interfaces. `publish` stamps `id`/`at`, then
  calls `deliver`, which invokes every registered listener whose topic pattern
  matches — synchronously, in registration order, on the caller's thread.
- Discovered `listener`s are registered into `LocalBus` at startup (the same
  discovery pass DI already runs).

Because it's the default binding, this code just works with no `module` entry:

```x
async entry main(args: String[]) -> Integer {
    let flow = App.resolve(SignupFlow)
    flow.register("Ada", "ada@x.dev")   // Welcome.greet runs before this returns
    return 0
}
```

### Replacing it in the app module

To change transport, `bind` a different implementation — producers and listeners
are unchanged:

```x
// An out-of-process publisher: serialize the payload and put it on a queue.
class KafkaPublisher implements PublisherService {
    deps { conn: net.Conn }
    producer publish(topic: String, payload: Json) {
        let line = topic + "\t" + json.stringify(payload)   // serialization!
        net.sendText(conn, line + "\n")
    }
}

module App {
    bind PublisherService -> KafkaPublisher as singleton
    // ConsumerService can stay LocalBus, or be replaced by a queue consumer
    // that parses incoming lines with json.parse and calls deliver.
}
```

This is where `std/json` and the event system meet: an in-process bus passes the
`Json` value by reference; an out-of-process bus `stringify`s it on publish and
`parse`s it on receive. The producer and listener never change.

## End-to-end example

```x
import "std/json.x"

interface Mailer { consumer send(to: String, body: String) }
class StdoutMailer implements Mailer {
    deps {}
    consumer send(to: String, body: String) {
        system.stdout.writeln("mail to " + to + ": " + body)
    }
}

class Shop {
    deps { events: PublisherService }
    producer checkout(item: String, total: Number) {
        let p = json.object()
        p = json.set(p, "item", json.str(item))
        p = json.set(p, "total", json.num(total))
        events.publish("order.paid", p)
    }
}

class Receipts {
    deps { mailer: Mailer }
    listener email(e: Event) on "order.paid" {
        mailer.send("buyer@x.dev",
            "Paid " + json.getNumber(e.payload, "total") + " for "
                    + json.getString(e.payload, "item"))
    }
}

class Audit {
    deps {}
    listener log(e: Event) on "order.*" {       // prefix match
        system.stdout.writeln("[audit] " + e.topic + " " + json.stringify(e.payload))
    }
}

async entry main(args: String[]) -> Integer {
    let shop = App.resolve(Shop)
    shop.checkout("book", 29.0)   // Receipts.email AND Audit.log both fire
    return 0
}

module App {}   // default LocalBus; add a bind to change transport
```

## Semantics & decisions

- **An event is `{ topic, payload: Json, id, at }`.** The payload is always a
  serializable `Json`, so any event can be logged, replayed, or sent off-box.
- **`listener name(e: Event) on "topic"`** is the new kind — a `consumer` the
  runtime invokes on matching publishes. It may declare `deps`.
- **Topic matching**: exact, or `prefix.*`. (Full glob/regex is out of scope.)
- **Delivery**: the default is **synchronous, in-order, in-process** (easy to
  reason about and test). Async/queued delivery is a binding choice, not a
  language change.
- **Discovery**: listeners register automatically via the existing DI discovery
  pass. `PublisherService`/`ConsumerService` resolve to `LocalBus` unless an app
  `bind`s otherwise.
- **Errors**: an interrupt signalled inside a listener propagates to `publish`'s
  caller under `LocalBus` (so a `try`/`catch` around `publish` works); other
  transports define their own policy. Whether one failing listener stops the rest
  is a hit-policy knob (default: stop), TBD.

## Out of scope / future

- **Typed payloads** — a `listener greet(e: UserCreated)` with a compiler-checked
  payload type, once compile-time reflection can derive `toJson`/`fromJson`.
- **Async / buffered delivery**, retries, dead-lettering — left to alternate
  `ConsumerService` implementations.
- **Ordering guarantees** across topics, and **back-pressure**.
- **Wildcard/glob topic matching** beyond a trailing `.*`.
- A **`Listener` handle type** (used in `ConsumerService.register` above) needs
  first-class function values or a small generated trampoline per listener —
  resolved during implementation.

## Relationship to other features

- **Serialization** ([`std/json`](../serialization.md)) — provides the payload
  and the wire format for out-of-process buses. **Prerequisite, shipped.**
- **DI** — makes `PublisherService`/`ConsumerService` and listeners discoverable
  and replaceable. **Reused as-is.**
- **Atoms / machines** — a listener is a natural place to `dispatch` an atom
  transition or advance a [machine](../machines.md), turning external events into
  state changes.
- **Interrupts** — listener failures surface as resumable conditions, not panics.
