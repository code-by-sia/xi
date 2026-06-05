# Atoms (active-state stores)

An **`atom`** holds a single **immutable `state` value** and lets you change it
only through **`transition`s** — pure reducers `(currentState, payload?) →
newState`. Dispatching a transition computes the next value and swaps the held
one (the old value is dropped). This is the Redux store / Clojure atom model.

```x
state Cart = { items: Integer, total: Number }   // an immutable state type

atom cart {
    initial Cart { items: 0, total: 0.0 }
    transition addItem(s: Cart, price: Number) -> Cart {
        return Cart { items: s.items + 1, total: s.total + price }
    }
    transition clear(s: Cart) -> Cart { return empty Cart }
}
```

```x
cart.addItem(9.99)        // dispatch: next = addItem(current, 9.99); held value swapped
cart.clear()
let n = cart.current.items   // read the current immutable snapshot
```

## Semantics

- **`state T = { ... }`** declares an immutable state type (a compound type; you
  replace it, never mutate it in place).
- **`atom name { initial <value>  transition* }`** declares one holder seeded
  with `initial`.
- A **`transition f(s: T, p: P) -> T`** is a reducer. Calling `name.f(p)` passes
  the *current* state as `s` automatically — you supply only the payload — then
  stores the returned value. A transition with no payload is just `f(s: T) -> T`.
- **`name.current`** reads the current value.

## Lowering

```c
static xc_Cart_t __atom_cart;                         /* the holder */
static xc_Cart_t xc_cart__addItem(xc_Cart_t s, xc_number_t price) { /* reducer */ }
/* cart.addItem(9.99)  ->  (__atom_cart = xc_cart__addItem(__atom_cart, 9.99)) */
/* cart.current        ->  __atom_cart */
```

Holders are seeded at startup. There is no runtime machinery beyond the reducer
call and the assignment — and (currently) a single, program-global instance per
atom.

## Notes & limits

- One global instance per `atom` (no per-instance stores yet).
- Transitions are synchronous and single-threaded.
- A `state` whose fields use only `String[]`/user-type arrays is fine; primitive
  arrays (`Integer[]`) aren't supported yet (a general limitation).

A higher-level **state machine** layer (named states, a legal-transition graph,
machine-wide `data`, and `where` guards) is also available — see
[Machines](machines.md).

See `examples/atom_demo.xi`.
