# Proposal: Events — remaining work

> The event system is **implemented** — see [Events](../events.md) for the full,
> current model (typed DTOs, `events.publish(topic, dto)`, typed
> `listener (e: T) on "topic"`, the type-erased envelope, the default in-memory
> `MemoryBus`/`MemoryConsumer` with no serialization, and replaceable external
> transports via `Events.encode`/`decode`/`dispatch`). This page tracks only the
> parts **not yet built**.

## Open items

- **Primitive number/bool arrays in payloads.** The derived codec now encodes
  array fields element-by-element — `String[]` and arrays of `event` types work
  ([Events](../events.md), `examples/event_array_demo.xi`). Arrays of primitive
  numbers/bools (`Integer[]`, `Number[]`, `Bool[]`) still can't be *fields* of a
  payload because the language doesn't yet emit those array typedefs for struct
  members (a general limitation, not codec-specific); the codec already handles
  them once that lands.

- **Async / buffered delivery.** Delivery today is synchronous within the pump
  (`Events.run` drains the in-memory queue on the calling thread). A
  `ConsumerService` that delivers on a worker thread, batches, retries, or
  dead-letters is a transport concern that can be added without language changes.

- **The topic inside the listener.** A listener receives the typed DTO only. For
  wildcard subscriptions (one listener over several topics) it may also want the
  concrete topic that fired — e.g. a second optional parameter or an accessor.

- **Schema / version negotiation on the wire.** External transports serialize by
  the event's type name; evolving an `event`'s shape across producer/consumer
  versions has no built-in versioning story yet.

- **Multiple external buses at once.** Routing different event topics to
  different bound transports (rather than a single `PublisherService`) is not yet
  expressible.

## Background

The original design notes (string topics with `Json` payloads, and an earlier
`Events.emit` builtin) have been superseded by the typed model described in
[Events](../events.md), which is the source of truth.
