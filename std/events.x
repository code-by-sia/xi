// std/events — pub/sub event system.  import "std/events.x"
//
// Producers call `bus.publish(topic, payload)` where `bus` is an injected
// `PublisherService`.  `listener` methods declared in any class are
// auto-discovered and receive matching events via the runtime dispatch table.
//
// The default implementation (`LocalBus`) is synchronous and in-process;
// replace it by binding a different `PublisherService` in your app module.

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
