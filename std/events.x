// std/events — typed pub/sub event system.  import "std/events.x"
//
// A producer publishes any DTO under a topic through an injected
// `PublisherService`:
//
//     deps { events: PublisherService }
//     events.publish("order.paid", OrderPaid { ... })
//
// A `listener` subscribes to a topic and receives the TYPED DTO — no JSON:
//
//     listener onPaid(e: OrderPaid) on "order.paid" { ... }
//
// An event travels as a type-erased envelope (`Event`: topic + type name + an
// opaque pointer to the typed value). The ONLY difference between application
// and external events is which transport is bound:
//
//   * default (MemoryBus / MemoryConsumer): the envelope is kept in an in-memory
//     queue and the typed value is passed straight through — NO serialization.
//   * developer's: serialize on publish, ship over the network, then deserialize
//     and re-dispatch on the other side (using Events.encode / Events.decode).
//
// The pump (`ConsumerService.run`) drains delivered events to the listeners.

import "std/json.x"

// ── Transport seams (replace these to go external) ──────────────────────────

interface PublisherService {
    // Producers call `publish(topic, dto)`; the compiler wraps the DTO into the
    // `Event` envelope, so an implementation receives a single `Event`.
    producer publish(e: Event)
}

interface ConsumerService {
    // The pump: deliver queued/received events to their listeners.
    consumer run()
}

// ── Runtime bridge: the in-memory queue ─────────────────────────────────────

extern "C" {
    producer xstd_eventq_push(e: Event)
    mapper   xstd_eventq_len() -> Integer
    producer xstd_eventq_shift() -> Event
}

// ── Default in-process transport: a queue, no serialization ─────────────────

class MemoryBus implements PublisherService {
    deps {}
    producer publish(e: Event) {
        xstd_eventq_push(e)
    }
}

class MemoryConsumer implements ConsumerService {
    deps {}
    consumer run() {
        while xstd_eventq_len() > 0 {
            Events.dispatch(xstd_eventq_shift())
        }
    }
}
