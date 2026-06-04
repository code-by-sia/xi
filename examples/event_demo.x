// Event system demo — pub/sub with the `listener` kind.
//
// Run:  xc examples/event_demo.x -o event_demo && ./event_demo

import "std/json.x"
import "std/events.x"

// ── Domain ────────────────────────────────────────────────────────────────

interface Mailer {
    consumer send(to: String, body: String)
}

class StdoutMailer implements Mailer {
    deps {}
    consumer send(to: String, body: String) {
        system.stdout.writeln("mail to " + to + ": " + body)
    }
}

// ── Producer ──────────────────────────────────────────────────────────────

interface Store {
    producer checkout(item: String, total: Number)
}

class Shop implements Store {
    deps { bus: PublisherService }

    producer checkout(item: String, total: Number) {
        let p = json.object()
        p = json.set(p, "item", json.str(item))
        p = json.set(p, "total", json.num(total))
        bus.publish("order.paid", p)
    }
}

// ── Listeners ─────────────────────────────────────────────────────────────

class Receipts {
    deps { mailer: Mailer }

    listener email(e: Event) on "order.paid" {
        let item  = json.getString(e.payload, "item")
        let total = json.getNumber(e.payload, "total")
        mailer.send("buyer@x.dev", "Paid " + total + " for " + item)
    }
}

class Audit {
    deps {}

    listener log(e: Event) on "order.*" {
        system.stdout.writeln("[audit] " + e.topic + " " + json.stringify(e.payload))
    }
}

// ── Entry ─────────────────────────────────────────────────────────────────

async entry main(args: String[]) -> Integer {
    let shop = App.resolve(Store)
    shop.checkout("book", 29.0)    // Receipts.email AND Audit.log both fire
    shop.checkout("pen",   3.5)
    return 0
}

module App {}   // default LocalBus; add a `bind PublisherService -> KafkaBus` to swap
