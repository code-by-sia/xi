// Typed application & external events.
//
// `event T { … }` declares a typed event. `Events.emit(value)` dispatches it
// directly to typed `listener (e: T)` methods — in-process, with NO serialization.
// Binding a non-default PublisherService makes emit ALSO serialize and ship the
// event on the wire (serialize only at the boundary). An inbound transport hands
// received messages to `Events.deliver(topic, json)`, which deserializes and
// dispatches to the same typed listeners.
import "std/json.x"
import "std/events.x"

event OrderPaid { id: String, item: String, total: Number }

// ── A producer emits the domain value it already has — no Json building ──────
interface Store { producer checkout(item: String, total: Number) }
class Shop implements Store {
    deps {}
    producer checkout(item: String, total: Number) {
        Events.emit(OrderPaid { id: "o-42", item: item, total: total })
    }
}

// ── Typed listeners: the parameter TYPE is the subscription ──────────────────
interface Mailer { consumer send(to: String, body: String) }
class StdoutMailer implements Mailer {
    deps {}
    consumer send(to: String, body: String) { system.stdout.writeln("mail " + to + ": " + body) }
}

class Receipts {
    deps { mailer: Mailer }                 // listeners get their own deps wired
    listener onPaid(e: OrderPaid) {
        mailer.send("buyer@x.dev", "Paid " + e.total + " for " + e.item)
    }
}
class Audit {
    deps {}
    listener log(e: OrderPaid) { system.stdout.writeln("[audit] " + e.id + " " + e.item) }
}

// ── An external transport — serialize and ship (here, just print the bytes) ──
class WireBus implements PublisherService {
    deps {}
    producer publish(topic: String, payload: Json) {
        system.stdout.writeln("[wire>] " + topic + " " + json.stringify(payload))
    }
}

async entry main(args: String[]) -> Integer {
    let shop = App.resolve(Store)

    system.stdout.writeln("== emit: typed local dispatch + external publish ==")
    shop.checkout("book", 29.0)

    system.stdout.writeln("== inbound from the wire: deserialize + typed dispatch ==")
    let body = "{\"id\":\"r1\",\"item\":\"remote-widget\",\"total\":99}"
    Events.deliver("OrderPaid", json.parse(body))
    return 0
}

// Replace the publisher to make events external; producers/listeners are unchanged.
module App {
    bind PublisherService -> WireBus as singleton
}
