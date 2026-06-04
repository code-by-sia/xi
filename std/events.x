// std/events — pub/sub event system.  import "std/events.x"
//
// Two ways to send events:
//
//  1. Typed application events (no serialization). Declare `event T { … }`, then
//     `Events.emit(T { … })` dispatches the value directly to typed `listener
//     (e: T)` methods, in-process. The `Events` facility is built into the
//     language; you do not inject it.
//
//  2. String-topic events. A producer injects a `PublisherService` and calls
//     `bus.publish(topic, payload)` with a `Json` payload; `listener (e: Event)
//     on "topic"` methods receive them. The default `LocalBus` dispatches
//     in-process and synchronously.
//
// Crossing the process boundary: bind a non-default `PublisherService`
// (outbound) — `Events.emit` then ALSO serializes the typed event and publishes
// it on the wire. An inbound transport (a `ConsumerService`) reads wire messages
// and calls `Events.deliver(topic, json)`, which deserializes and dispatches to
// the same typed listeners. Serialization happens only at the boundary.

import "std/json.x"

// ── Event ───────────────────────────────────────────────────────────────────
// What a listener receives: the topic that fired and its serializable payload.
type Event = {
    topic:   String,
    payload: Json
}

// ── Runtime bridge ─────────────────────────────────────────────────────────

extern "C" {
    producer xstd_event_publish(topic: String, payload: Json)
}

// ── PublisherService interface ─────────────────────────────────────────────

interface PublisherService {
    producer publish(topic: String, payload: Json)
}

// ── LocalBus: default in-process, synchronous implementation ──────────────

class LocalBus implements PublisherService {
    deps {}

    producer publish(topic: String, payload: Json) {
        xstd_event_publish(topic, payload)
    }
}

// ── ConsumerService: the inbound seam (the "system listener" to replace) ─────
// An external transport implements `run` to pull a message off the wire and feed
// it to `Events.deliver(topic, payload)`, which routes it to the typed listeners.
// The default does nothing (in-process apps need no inbound pump).
interface ConsumerService {
    consumer run()
}

class LocalConsumer implements ConsumerService {
    deps {}
    consumer run() { }
}
