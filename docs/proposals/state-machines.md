# Proposal: Atoms & state machines

> **Status: Draft — design for review.** Two related features: `atom` (an
> active-state / Redux-style store) and `machine` (a state machine built on top).
> Not implemented.

## Summary

Two layers:

1. **`atom`** — a mutable holder of an **immutable** `state` value. You change
   it only through **`transition`s**: pure functions `(currentState, payload?) →
   newState`. The atom computes the next value and swaps its pointer, dropping
   the old one. (This is the Redux store / Clojure atom model.)
2. **`machine`** — a state machine: named states, an initial (and optional
   terminal) state, and **arrows** that both name a transition and declare which
   source states it's legal from. An illegal transition **signals an interrupt**,
   so the caller can `recover` (stay put) or `skip`.

These reuse what X already has: a `transition` is the **`reducer`** intent
`(state, input) → state`; immutability is X's value semantics; illegal moves use
the **[interrupt](../interrupts.md)** feature; and an atom can be **DI-resolved**
so components share one store.

## Layer 1 — `atom` (active-state)

```x
state Cart = { items: Integer, total: Number }   // an immutable STATE type

atom cart {
    initial Cart { items: 0, total: 0.0 }
    transition addItem(s: Cart, price: Number) -> Cart {
        return Cart { items: s.items + 1, total: s.total + price }
    }
    transition clear(s: Cart) -> Cart { return empty Cart }
}
```

```x
cart.addItem(9.99)        // dispatch: next = addItem(current, 9.99); swap pointer
cart.clear()
let snap = cart.current   // read the current immutable snapshot
```

### Semantics

- **`state T = { ... }`** declares an immutable state type (a compound type
  tagged as a state; it may not be mutated in place — only replaced).
- **`atom name { initial <value>  transition* }`** declares one holder of a
  `state` value, seeded with `initial`.
- A **`transition f(s: T, p: P) -> T`** is a pure reducer. Calling `name.f(p)`
  passes the *current* state as `s` automatically — you supply only the payload —
  computes the new state, and stores it.
- **`name.current`** reads the current value (an immutable snapshot).

### Lowering

```c
static xc_Cart_t __atom_cart = /* initial */;
static void xc_atom_cart_addItem(xc_number_t price) {
    __atom_cart = xc_cart__addItem(__atom_cart, price);
}
/* name.current -> __atom_cart */
```

Single-threaded, no runtime machinery. (An atom may also be exposed through DI as
a shared singleton store — future.)

## Layer 2 — `machine` (state machine)

```x
machine Door {
    states   Closed, Open, Locked
    initial  Closed
    terminal -                       // none here (could list terminal states)

    open    : Closed        -> Open
    close   : Open          -> Closed
    lock    : Closed, Open  -> Locked     // multiple legal sources
    unlock  : Locked        -> Closed
}
```

```x
let d = Door.start()      // immutable machine value at Closed
let d2 = d.open()         // Closed -> Open  (legal)
let d3 = d2.lock()        // Open -> Locked
let d4 = d3.open()        // illegal from Locked -> signals IllegalTransition
system.stdout.writeln(d3.state + " terminal? " + d3.isTerminal())
```

### Semantics

- **`states`** lists the named states (a small enum). **`initial`** and optional
  **`terminal`** name states in that set.
- Each **`name : from (, from)* -> to`** declares a transition *and* its legal
  source states.
- A machine value is **immutable**: `d.open()` returns the advanced machine (so
  `d = d.open()`), mirroring X's value semantics. To get Redux-style mutation,
  hold a machine in an `atom`.
- **Generated API**: the state enum, `Door.start()`, one method per transition
  (`open`, `close`, …), `.state`, `.isTerminal()`, and `.can(open)`.

### Illegal transitions → an interrupt

The machine auto-declares an interrupt and signals it on an illegal move:

```x
interrupt IllegalTransition { from: String, to: String }
```

```x
try {
    d = d.open()                 // from Locked: illegal
} catch e: IllegalTransition {
    system.stdout.writeln("can't " + e.from + "->" + e.to)
    recover                      // stay in the current state
    // or: skip                  // abandon
}
```

`recover` keeps the machine in its current state; `skip` abandons the attempt.
This is exactly the [interrupt](../interrupts.md) model.

## Integration

- **`reducer`/`transition`**: a transition is the reducer intent made first-class.
- **DI**: `atom`s (and machine-backed atoms) can be resolved via `App.resolve`,
  giving a shared store across components.
- **Decision tables**: a transition body can use a `decision` to pick the next
  state from conditions.
- **Interrupts**: illegal moves are resumable conditions, not panics.

## Implementation sketch

- `atom`: emit the holder global + a dispatch function per transition; `.current`
  reads the global. The `transition` bodies are ordinary reducer bodies.
- `machine`: needs a **minimal enum** for the state set (X has no sum types yet —
  this is the one prerequisite). Generate the enum, a value carrying the current
  state, guarded transition functions (check the source state; on mismatch emit a
  `signal IllegalTransition {...} recover {...}`), and the queries.
- The `atom` (state = struct) needs no new type machinery and can land first; the
  `machine` follows once the enum exists.

## Out of scope / future

- **States that carry data** (e.g. `Running { startedAt }`) — needs real
  sum/algebraic types.
- **Mutable machine instances** vs the immutable-value model above; multiple
  instances vs a singleton.
- **History / time-travel**, entry/exit actions, and `async` transitions.
- Static reachability / dead-state checks on the graph.

## Decisions on record

- The active-state primitive is **`atom`**; transitions use a dedicated
  **`transition`** keyword.
- Machine states are **data-less named states** (a minimal enum) for the first
  version.
- Illegal transitions **signal an interrupt** (`recover` = stay, `skip` =
  abandon).
- `atom` can ship before `machine` (which needs the enum first).
