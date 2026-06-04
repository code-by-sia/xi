# Proposal: Atoms & state machines — remaining work

> **Implemented** — both layers ship today:
> - **`atom`** (active-state store) — see [Atoms](../atoms.md).
> - **`machine`** (finite state machine) — named states, `initial`/`terminal`,
>   multi-source transitions, **machine-wide `data`**, transition **parameters**,
>   **`where` guards**, **`update`** clauses, **`.can(...)`**, and illegal moves
>   via the `IllegalTransition` interrupt. See [Machines](../machines.md).
>
> This page tracks only what is **not yet built**.

## Open items

- **Per-state data.** `data` is machine-wide context shared by every state.
  Distinct fields per state (e.g. `Running { startedAt }` vs `Idle {}`) need real
  sum / algebraic types and are out of scope until those exist.

- **Atoms via DI.** An `atom` is currently a single program-global holder accessed
  by name (`cart.addItem()`, `cart.current`). Exposing it as an injectable shared
  store (so components depend on an interface backed by the atom) needs a design
  for how an atom satisfies an interface.

- **Per-instance stores.** Both `atom`s and machine-backed stores are global
  singletons today; multiple independent instances aren't expressible.

- **History / time-travel, entry/exit actions, `async` transitions.**

- **Static checks** on the machine graph: reachability, dead states, and
  exhaustiveness of guards.

- **Multi-line guards.** A transition `where` guard is collected to the end of its
  line; a guard spanning several lines isn't supported (use a helper predicate).

- **Primitive arrays in `state`/`data`.** Fields typed `Integer[]` etc. aren't
  supported yet — a general array limitation, not specific to atoms/machines.

## Background

The original two-layer design (atoms as the active-state primitive; machines as a
named-state graph that signals an interrupt on illegal moves) is realized as
described in [Atoms](../atoms.md) and [Machines](../machines.md), which are the
source of truth.
