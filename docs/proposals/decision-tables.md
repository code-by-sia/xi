# Proposal: Decision tables — the tabular form

> **Status: Draft — design for review.** Extends the **shipped** `decision`
> *when-form* (see [Decision tables](../decisions.md)) with a true tabular form.
> Not yet implemented.

## Why

The shipped `when`-form is, honestly, `match` with boolean guards:

```x
decision tier(score: Number) -> String {
    when score >= 700 => "high"
    else              => "low"
}
```

That's useful but not *more* than `match`. A real decision table earns its name
by doing things `match` cannot:

| Capability | `match` | tabular `decision` |
|------------|---------|--------------------|
| Several **inputs** as columns | one subject | N input columns |
| Several **outputs** per rule | one result | M outputs at once |
| **Hit policy** | always first | `first` / `unique` / `collect` |
| Return **all** matches | no | `collect` → a list |
| Order independence | no | `unique` is order-free |

This proposal adds that tabular form. (Static completeness/overlap *proofs* are
intentionally **out of scope** here; the constrained cell DSL below keeps them
possible as a later addition.)

## The two forms

`decision` keeps both shapes under one keyword:

- **when-form** (shipped) — sparse rules, single output, `hit first`.
  `decision name(params) -> T { when … => … else => … }`
- **table-form** (this proposal) — a grid with `in`/`out` declarations.

The body's first tokens disambiguate: `when`/`else` ⇒ when-form; `in`/`out`/`|`
⇒ table-form.

## Table-form syntax

```x
decision shipping {
    in  weight: Number
    in  zone:   String
    out cost:    Number
    out express: Bool
    hit first

    //  weight     zone                => cost  express
    |   <= 1     | "US"                =>   5  | true  |
    |   <= 1     | in {"CA", "MX"}     =>  10  | false |
    |   [1 .. 5] | -                   =>  15  | false |
    |   -        | -                   =>  25  | false |   // default
}
```

- `in <name>: <Type>` declares an input column (becomes a parameter).
- `out <name>: <Type>` declares an output column.
- Each rule: `| <cell> | … => <expr> | … |` — input cells before `=>`, output
  expressions after, one per `out`, in declaration order.

### Synthesized signature & result

The `in`s become the parameters. The `out`s become the result:

- **one `out`** → the decision returns that scalar type;
- **several `out`s** → the decision returns a compiler-synthesized record
  `{ cost: Number, express: Bool }` (named `<Decision>Out`, e.g. `ShippingOut`),
  so callers read fields:

```x
let s = shipping(0.5, "US")
system.stdout.writeln(s.cost + " express=" + s.express)
```

### Cell DSL (constrained + escape hatch)

Each input cell is a **unary test** whose implicit subject is that column's
input:

| Cell | Means |
|------|-------|
| `-` | any (wildcard) |
| `42` / `"US"` / `Gold` | equals |
| `>= n`, `> n`, `<= n`, `< n` | comparison |
| `[a .. b]` | inclusive range |
| `in { a, b, c }` | membership |
| `not <test>` | negation |
| `?( <expr> )` | **escape**: any boolean expression over the inputs (may call predicates / use deps) |

The `?( … )` escape is what makes the table as expressive as the when-form when
you need it; the constrained tests are what a future analysis pass could reason
about. Open-ended ranges are written with comparisons (`> 5`); `[a..b]` is the
only range sugar in this version.

## Hit policies

```
hit first    // top-to-bottom; first matching row wins (default)
hit unique   // exactly one row must match; else runtime panic
hit collect  // ALL matching rows; returns a list of outputs
```

- **`first`** — evaluate rows in order, return the first match. A trailing
  `-, … , -` row is the default. If none matches and there is no default → panic.
- **`unique`** — every row is tested; exactly one must match. Zero or more than
  one → runtime panic with the decision name. (A catch-all default is therefore
  illegal under `unique`.) Order does not matter.
- **`collect`** — every row is tested; the outputs of *all* matching rows are
  returned as a list (`Number[]` for a single `out`, `<Decision>Out[]` for
  several). Optional aggregator for a single numeric `out`:
  `hit collect sum | min | max | count` → returns the aggregate (`count` →
  `Integer`).

`priority` and `any` are noted as future work.

## Relationship to the when-form

The when-form is sugar for a single-input, single-output, `first` table — they
share lowering. Authors pick whichever reads better: `when` for a handful of
guarded cases, the grid for genuine multi-dimensional rules.

## Semantics & lowering

A row's input cells become a conjunction of tests on the inputs; the cell DSL
lowers per the table above (`[a..b]` → `a <= x and x <= b`, `in {…}` → a chain of
`==`, `-` → omitted, `?(e)` → `e`).

- **first** → an `if <row-cond> { return <outputs> } …` chain + default — exactly
  the existing when-form lowering, generalized to a result record.
- **unique** → evaluate each row condition into a bool, sum the matches, assert
  `== 1` (a runtime helper `decision_fail(name)` panics otherwise), return the
  single match.
- **collect** → the row count `M` is known at compile time, so codegen allocates
  a fixed-capacity (`M`) result buffer, appends each matching row's output, and
  sets the length — no generic growable-array support needed. Aggregators fold
  over the matches instead of building a list.

Multiple outputs synthesize the `<Decision>Out` record type (and its `[]` / `!`
shapes as needed), analogous to how `Bytes`/user types get theirs.

DI and predicates work as in the when-form: a table `decision` can be an
interface method (injectable), and `?( … )` cells can call predicates and use
injected deps.

## Out of scope (future)

- **Static completeness / overlap / dead-rule analysis** (the constrained DSL is
  designed to allow it later; arbitrary `?( … )` cells are exempt).
- **`priority`** and **`any`** hit policies.
- **Rule metadata / audit** (per-row id/description, render-as-truth-table).

## Decisions on record

- Add a **table-form** alongside the shipped when-form, same `decision` keyword.
- Capabilities this round: **multi-input / multi-output grid** and **hit
  policies** (`first`, `unique`, `collect` + aggregators).
- Cell DSL is **constrained unary tests + a `?( expr )` escape hatch**.
- Static gap/overlap checks and audit metadata are **deferred**.
- Spec first (this document), implement later.
