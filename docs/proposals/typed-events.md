# Proposal: Application & external events — typed in-process payloads + replaceable transport

> **Status: Draft — design for review.** Extends the **shipped** event system
> ([Events](../events.md)) with *typed* application events that skip
> serialization in-process, while keeping serialization for events that cross a
> process boundary. Builds on [serialization](../serialization.md) and
> [dependency injection](../language-guide.md). Not yet implemented.

## Why

The shipped event system has one payload shape — a `Json` value addressed by a
string topic:

```x
bus.publish("order.paid", payload)            // payload : Json
listener onPaid(e: Event) on "order.paid" { … e.payload … }
```

That is exactly right for an event **leaving the process**: a wire needs a
serialized, self-describing payload. But it is wasteful and loose for an event
that **stays in the process**:

- You build a `Json` tree (`json.object()` / `set` / …) instead of passing the
  domain value you already have.
- The listener re-reads fields out of `Json` (`getString`, `getNumber`) with no
  type checking — a renamed field fails at runtime, not compile time.
- Even though `LocalBus` passes the `Json` *by reference* (it does not stringify
  in-process today), you still paid to **construct** and **deconstruct** it.

We want **one** event system that serves both needs:

| | Application (in-process) | External (cross-process) |
|---|---|---|
| Payload | the **typed** domain value | serialized (`Json`/bytes) |
| Cost | direct call, **no serialize/deserialize** | serialize once at the boundary |
| Safety | compile-checked fields | codec at the edge |
| Transport | built-in, default | **replaceable** publisher + listener |

The principle: **serialize only at the process boundary.** In-process events
carry the typed value directly.

## The model: two tiers, one `listener`

### 1. Typed events (`event`)

A new declaration introduces a typed event — a payload type plus an
auto-derived JSON codec that is used *only* when the event crosses a boundary:

```x
event OrderPaid { id: String, item: String, total: Number }
```

This is a compound type (`OrderPaid` is a normal value) for which the compiler
also derives `toJson(OrderPaid) -> Json` and `fromJson(Json) -> OrderPaid`. Those
codecs are emitted but **only called by external transports** — application
dispatch never touches them.

### 2. Producers emit typed values

A producer depends on the injected **`EventBus`** and emits the value it already
holds — no `Json` construction:

```x
class Shop {
    deps { events: EventBus }
    producer checkout(item: String, total: Number) {
        events.emit(OrderPaid { id: "o1", item: item, total: total })
    }
}
```

### 3. Listeners are typed; the parameter type is the channel

A typed listener names its event by **type** — there is no string topic to match,
so a typo can't silently miss:

```x
class Receipts {
    deps { mailer: Mailer }
    listener onPaid(e: OrderPaid) {          // subscribes to OrderPaid
        mailer.send("buyer@x.dev", "Paid " + e.total + " for " + e.item)
    }
}
```

In-process, `events.emit(OrderPaid{…})` calls `Receipts.onPaid` **directly with
the struct**. No `Json`, no serialization, full type checking.

> The shipped string-topic form (`listener f(e: Event) on "topic"`, `Json`
> payload) **stays** — it remains the right tool for dynamic/loosely-typed
> events and *is* the on-the-wire representation of typed events (below).

## Crossing the boundary: replaceable transport

External delivery reuses the **shipped seam**. Two replaceable roles:

- **Outbound — `PublisherService`** (already shipped: `publish(topic, Json)`).
  The default `LocalBus` does nothing external. Bind an external one to ship
  events off-box.
- **Inbound — `ConsumerService`** (the "system listener" to replace). It pulls
  messages off a transport, deserializes, and re-injects them as in-process
  typed events so the *same* `listener`s fire.

Each `event T` has a canonical wire **topic** (its type name, or an explicit
`event T topic "order.paid"`). `emit(e: T)` does, in order:

1. **Application tier** — invoke every in-process `listener (e: T)` directly with
   the value. *(No serialize.)*
2. **External tier** — *iff* a non-local `PublisherService` is bound, also call
   `publish(topicOf(T), toJson(e))`. *(Serialize once, here, at the edge.)*

Inbound, a bound `ConsumerService` receives `(topic, Json)` and the
compiler-generated router maps `topic → fromJson_T → emit-local(T)`, so a remote
event becomes a typed in-process dispatch (deserialize once, at the edge).

```x
// Outbound: serialize and ship. User implements only the byte transport.
class KafkaBus implements PublisherService {
    deps { conn: net.Conn }
    producer publish(topic: String, payload: Json) {
        net.sendText(conn, topic + "\t" + json.stringify(payload) + "\n")
    }
}

// Inbound ("system listener"): receive, hand (topic, Json) to the router.
class KafkaConsumer implements ConsumerService {
    deps { conn: net.Conn }
    consumer run() {
        let line = net.recvText(conn, 65536)
        let tab  = text.indexOf(line, "\t")
        deliver(text.substring(line, 0, tab),                 // topic
                json.parse(text.substring(line, tab + 1, text.length(line))))
    }
}

module App {
    bind PublisherService -> KafkaBus      as singleton   // replace the publisher
    bind ConsumerService  -> KafkaConsumer as singleton   // replace the listener
}
```

`deliver(topic, Json)` is the compiler-provided router (the inbound counterpart of
`emit`). Producers and `listener`s never change when you swap transport — only the
module bindings do.

## Why this stays efficient for application events

- `emit(e: T)` lowers to a direct loop over typed function pointers taking
  `xc_T_t` — the same machinery as today's listeners, but typed. No `Json`.
- `toJson_T` / `fromJson_T` are dead code paths unless an external transport is
  bound; with only `LocalBus`, the linker can drop them.
- The struct is passed by value (or `const*`) exactly like any X call.

## Lowering sketch

For each `event T`:

```c
typedef struct { /* fields */ } xc_T_t;          /* the payload */
static xc_Json_t xc_tojson_T(xc_T_t);            /* derived codec (edge only) */
static xc_T_t    xc_fromjson_T(xc_Json_t);       /* derived codec (edge only) */

/* application tier: typed registry, filled at startup from typed listeners */
typedef void (*xc_lh_T)(xc_T_t);
static xc_lh_T xc_listeners_T[N]; static int xc_listeners_T_len;

static void xc_emit_local_T(xc_T_t e) {
    for (int i = 0; i < xc_listeners_T_len; i++) xc_listeners_T[i](e);
}
```

`events.emit(v)` where `v : T` lowers to:

```c
xc_emit_local_T(v);                              /* in-process, no serialize */
if (xc_external_publisher_bound)                 /* only if a transport is bound */
    xc_resolve_PublisherService().publish(topicOf_T, xc_tojson_T(v));
```

`deliver(topic, payload)` lowers to a generated switch over the program's event
topics: `if (eq(topic,"order.paid")) xc_emit_local_OrderPaid(xc_fromjson_OrderPaid(payload));`

A typed `listener onPaid(e: OrderPaid)` registers `&trampoline` into
`xc_listeners_OrderPaid` in `xc_events_init()` (same auto-discovery as today,
keyed by the parameter type instead of a string).

### The generics question

X has no generics yet, so `emit`/`deliver` cannot be ordinary generic methods.
They are **compiler-assisted**: codegen knows the static type at each `emit` call
site and the full set of `event` types, so it monomorphizes per type (the same
trick DI resolution already uses). Users implement only the byte-level
`publish(String, Json)` / `ConsumerService.run`; the typed fan-out and the
topic-routing switch are generated.

## Relationship to the shipped system

- `Event`, `listener … on "topic"`, `PublisherService`, `LocalBus` — **unchanged**.
- New: `event T`, typed `listener (e: T)`, `EventBus.emit`, `ConsumerService`,
  `deliver`, and the derived `toJson`/`fromJson`.
- The shipped `Json` form is now understood as the **wire form** of a typed event,
  and `PublisherService` as the **outbound transport seam** it already was.

## Out of scope / future

- **Async / buffered** delivery, retries, ordering, back-pressure — properties of
  a particular `ConsumerService`/transport, not the language.
- **Schema evolution / versioning** of `event` types on the wire.
- **Multiple external buses** at once (per-event routing to different transports).
- Replacing `toJson`/`fromJson` with a compact binary codec (the boundary is
  already codec-agnostic).

## Decisions on record

- Two tiers under one `listener` model: **typed application events** (no
  serialize) and **serialized external events**.
- A typed event is declared with **`event T { … }`** and addressed in-process by
  **type**; on the wire by a canonical **topic**.
- **Serialize only at the boundary.** In-process dispatch passes the struct
  directly; `toJson`/`fromJson` run only in external transports.
- External is achieved by **binding** a `PublisherService` (outbound) and a
  `ConsumerService` (inbound) — producers and listeners are untouched.
- `emit` / `deliver` are **compiler-assisted** (monomorphized per event type)
  until X has generics.
