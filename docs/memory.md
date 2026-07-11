# Memory management

Xi manages memory to honour its three commitments - **fast, least-dependency,
easy** - so there is **no garbage collector** (no runtime, no pauses) and **no
borrow checker to learn**. Instead it combines a simple default with region-based
reclamation where it matters.

You can write and ship real Xi programs without thinking about any of this. Read
on only when you have a **long-running** program (a server, a daemon, a big loop)
and want to keep its memory flat.

## The default: allocate-and-leak

Every heap value - a `String`, an array, a boxed object - is allocated and **never
individually freed**; the operating system reclaims everything when the process
exits.

That sounds surprising, but it's the *fastest* possible strategy for the common
case and it's completely safe:

- **CLIs and the compiler itself** run once and exit - freeing would be wasted
  work. Leaking is optimal.
- There are **no dangling pointers and no double-frees**, ever, because nothing is
  freed early.

The only place this is a problem is a process that runs for a long time and keeps
allocating. For those, Xi reclaims memory by **region**.

## Reclaiming by region (arenas)

A *region* is a scope whose allocations are all freed in one shot when it ends.
Xi uses regions in three places - two automatic, one you write yourself:

### Per-thread (automatic)

Each spawned thread allocates from its own arena, freed when the thread finishes.
So a worker thread reclaims everything it allocated on exit, and the main thread
is unaffected. This is safe because threads are **share-nothing**: data sent over
a channel is *copied*, so nothing a thread frees is still referenced elsewhere.
See [Threading](threading.md).

A **`Future<T>`** worker (an `async` call - see
[async/await](language-guide.md#concurrency-async--await)) is the one exception
to the per-thread arena: it does *not* create one, so its allocations leak onto
the shared heap and the result safely outlives the `await`. The result must
escape the worker, so leaking (the default) is exactly right here.

### Per-request (automatic)

`web.serve` runs each request under its own arena, freed once the response is
written. A server therefore reclaims each request instead of leaking it - its
heap stays flat across millions of requests. The response body is copied out
before the arena is freed, so it safely outlives the request. See [Web](web.md).

### `scope { }` (explicit)

For a long-running loop on the **main thread**, wrap the per-iteration work in a
`scope` block. Everything allocated inside is freed when the block ends:

```x
loop {
    scope {
        let line = "row-" + int_to_string(n)   // freed when the scope ends,
        process(line)                            // so the loop stays flat
    }
}
```

**The one rule** (the same for all three regions): a value must not **escape** its
region. Copy out anything you need to keep, and don't `return` a region-allocated
value out of a `scope` block. See `examples/concurrency/scope_demo.xi`.

## Why purity helps

Xi enforces that the pure function kinds - `mapper`, `predicate`, `projector` -
do no I/O and call no effectful function. That guarantee is what lets the compiler
treat a pure function's arguments as **borrowed**: it can pass them without a copy
and without any reference-count traffic, because a pure function provably cannot
stash them anywhere. You get this for free just by choosing the right
[function kind](language-guide.md#function-kinds).

## What's intentionally *not* here

- **No tracing GC.** It would add a runtime dependency and unpredictable pauses -
  both against the philosophy. Rejected outright.
- **No mandatory borrow checker.** Lifetimes are exactly the kind of concept that
  "costs a week" to learn; Xi avoids forcing them on you.
- **Automatic reference counting (ARC)** is *designed and deferred*: an opt-in
  runtime exists (build with `-DXC_ARC`), but full automatic per-value reclamation
  needs a larger compiler change and only adds value over arenas for objects that
  escape mid-computation - a disproportionate cost for the benefit. The arenas
  above already keep long-running programs flat.

## Practical guidance

| You're writing… | Do this |
|-----------------|---------|
| A CLI / one-shot tool | Nothing - leak-on-exit is ideal. |
| An HTTP server (`web.serve`) | Nothing - each request is reclaimed automatically. |
| Worker threads / `parallel` | Nothing - each thread reclaims on exit. |
| A long-running main-thread loop | Wrap each iteration's work in `scope { }`. |
| Anything that must outlive a region | Copy it out (don't let it escape). |
