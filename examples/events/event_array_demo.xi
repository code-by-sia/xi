// Array fields in event payloads serialize through the derived codec — including
// arrays of strings and arrays of nested events. An external transport encodes
// the event to JSON and decodes it back; the array fields survive the round-trip.
import "std/json.xi"
import "std/events.xi"
import "std/log.xi"

event Line  { sku: String, qty: Integer }
event Order { id: String, tags: String[], lines: Line[] }   // String[] and event[]

// A transport that serializes, "ships", then deserializes and re-dispatches —
// exercising Events.encode / Events.decode over the array fields.
class LoopBus implements PublisherService {
    deps { logger: Logger }
    producer publish(e: Event) {
        let body = json.stringify(Events.encode(e))
        logger.print("[wire] " + body)
        Events.dispatch(Events.decode(Events.topic(e), Events.type(e), json.parse(body)))
    }
}

class Sink {
    deps { logger: Logger }
    listener got(e: Order) on "order.created" {
        logger.print("order " + e.id + ": " + e.tags.len + " tags, " + e.lines.len + " lines")
        let i = 0
        while i < e.lines.len {
            logger.print("  " + e.lines.data[i].sku + " x" + e.lines.data[i].qty)
            i = i + 1
        }
    }
}

interface Shop { producer create() }
class ShopImpl implements Shop {
    deps { bus: PublisherService }
    producer create() {
        let tags  = ["new", "priority"]
        let lines = [ Line { sku: "A-1", qty: 2 }, Line { sku: "B-2", qty: 5 } ]
        bus.publish("order.created", Order { id: "o-7", tags: tags, lines: lines })
    }
}

async entry main(args: String[]) -> Integer {
    App.resolve(Shop).create()
    return 0
}

module App { bind PublisherService -> LoopBus as singleton }
