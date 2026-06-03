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
   terminal) state, optional machine-wide **`data`** (context), and **arrows**
   that name a transition, declare its legal source states, optionally **guard**
   it with `where`, and **`update`** the data. A move that's illegal (wrong
   source state, or guard false) **signals an interrupt**, so the caller can
   `recover` (stay put) or `skip`.

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

A machine has named **states**, an optional **data** context (machine-wide
extended state), and **transitions** with optional payloads, **`where` guards**,
and **`update`** clauses. The plain form (no data/guards/updates) is just an enum
FSM:

```x
machine Door {
    states  Closed, Open, Locked
    initial Closed
    open  : Closed       -> Open
    close : Open         -> Closed
    lock  : Closed, Open -> Locked
}
```

The full form carries data, guards transitions, and updates the data:

```x
machine Lock {
    states  Locked, Open
    initial Locked
    data { code: String = "1234", attempts: Integer = 0 }   // optional context

    unlock(attempt: String) : Locked -> Open
        where attempt == data.code                          // guard gates the move
        update { attempts: 0 }                              // produce the next context

    fail(attempt: String) : Locked -> Locked
        where attempt != data.code
        update { attempts: data.attempts + 1 }

    lock : Open -> Locked
}
```

```x
let l = Lock.start()          // Locked, code="1234", attempts=0
l = l.fail("0000")            // guard holds -> stays Locked, attempts=1
l = l.unlock("0000")          // guard fails -> illegal -> signals IllegalTransition
l = l.unlock("1234")          // -> Open, attempts reset to 0
system.stdout.writeln(l.state + " / attempts=" + l.data.attempts)
```

### Semantics

- **`states`** lists the named states (a small enum). **`initial`** and optional
  **`terminal`** name states in that set.
- **`data { f: T = init, ... }`** (optional) declares the machine-wide context
  with initial values. A machine value is then `{ state, data }`; without `data`
  it is just the state.
- A transition is **`name(params) : from (, from)* -> to`** with two optional
  clauses:
  - **`where <guard>`** — a boolean over the payload params and `data`. The move
    is legal only if the from-state matches **and** the guard holds.
  - **`update { field: expr, ... }`** — produces the next context; only the listed
    fields change (the rest carry over). `expr` may reference `data` (the old
    context) and the payload. (`update` is a reducer over the context.)
- A machine value is **immutable**: `l.unlock(x)` returns the advanced machine
  (`l = l.unlock(x)`), mirroring X's value semantics. To get Redux-style
  mutation, hold a machine in an `atom`.
- **Generated API**: the state enum, `Door.start()`, one method per transition,
  `.state`, `.data` (if any), `.isTerminal()`, and `.can(unlock, payload?)`.

### Illegal transitions → an interrupt

A move is **illegal** when the current state isn't an allowed source **or** the
`where` guard is false. The machine auto-declares an interrupt and signals it:

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
  this is the one prerequisite). Generate the enum and a value `{ state, data }`
  (data omitted when there's no `data` block). Each transition lowers to a guarded
  reducer: check the source state and evaluate `where`; on failure
  `signal IllegalTransition {...} recover {...}`; otherwise compute the next state
  and apply `update` to the context (carrying unlisted fields over). Also emit the
  queries (`state`, `data`, `isTerminal`, `can`).
- The `atom` (state = struct) needs no new type machinery and can land first; the
  `machine` follows once the enum exists.

## Out of scope / future

- **Per-state data** — distinct fields per state (e.g. `Running { startedAt }`).
  The `data` block here is **machine-wide context** shared by all states;
  per-state data needs real sum/algebraic types.
- **Mutable machine instances** vs the immutable-value model above; multiple
  instances vs a singleton.
- **History / time-travel**, entry/exit actions, and `async` transitions.
- Static reachability / dead-state checks on the graph.

## Decisions on record

- The active-state primitive is **`atom`**; transitions use a dedicated
  **`transition`** keyword.
- Machine states are **named states** (a minimal enum); a machine may also carry
  optional **machine-wide `data`** (context) declared inline `data { f: T = init }`.
- Transitions take explicit payload **params**, an optional **`where`** guard, and
  an optional **`update { field: expr }`** clause (partial; unlisted fields carry
  over).
- A move is illegal if the source state mismatches **or** the guard fails →
  **signal an interrupt** (`recover` = stay, `skip` = abandon).
- `atom` can ship before `machine` (which needs the enum first). Per-state data
  (vs machine-wide context) waits for sum types.
