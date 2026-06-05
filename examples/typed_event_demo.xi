// Typed events with a swappable transport.
//
// A producer publishes any DTO under a topic via an injected PublisherService;
// a `listener` subscribes to a topic and receives the TYPED DTO (no JSON). The
// only thing that differs between application and external events is which
// PublisherService / ConsumerService is bound:
//
//   * default (MemoryBus / MemoryConsumer): the event is queued in memory and the
//     typed value is passed straight to listeners — NO serialization.
//   * a developer's transport serializes on publish and deserializes on receive,
//     using Events.encode / Events.decode — JSON lives only inside that transport.
import "std/json.xi"
import "std/events.xi"

event OrderPaid { id: String, item: String, total: Number }

// ── Producer: publish any DTO under a topic ─────────────────────────────────
interface Store { producer checkout(item: String, total: Number) }
class Shop implements Store {
    deps { events: PublisherService }
    producer checkout(item: String, total: Number) {
        events.publish("order.paid", OrderPaid { id: "o-42", item: item, total: total })
    }
}

// ── Listeners: typed DTO, no JSON ───────────────────────────────────────────
interface Mailer { consumer send(to: String, body: String) }
class StdoutMailer implements Mailer {
    deps {}
    consumer send(to: String, body: String) { system.stdout.writeln("mail " + to + ": " + body) }
}

class Receipts {
    deps { mailer: Mailer }                       // a listener gets its own deps wired
    listener onPaid(e: OrderPaid) on "order.paid" {
        mailer.send("buyer@x.dev", "Paid " + e.total + " for " + e.item)
    }
}
class Audit {
    deps {}
    listener log(e: OrderPaid) on "order.paid" { system.stdout.writeln("[audit] " + e.id + " " + e.item) }
}

async entry main(args: String[]) -> Integer {
    let shop = App.resolve(Store)
    shop.checkout("book", 29.0)
    shop.checkout("pen", 3.5)

    // Drive the pump: deliver queued events to the listeners (no serialization).
    Events.run()
    return 0
}

// No binding needed — MemoryBus / MemoryConsumer are the defaults. To go external,
// bind your own PublisherService (serialize + send) and ConsumerService (receive
// + deserialize + Events.dispatch); producers and listeners stay unchanged.
module App {}
