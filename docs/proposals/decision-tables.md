# Proposal: Decision tables — remaining work

> **Core implemented** — the tabular `decision` form ships today: `in`/`out`
> columns, the cell DSL (`-`, comparisons, `[a .. b]`, `in {…}`, `not`, `?(…)`),
> and `hit first`. See [Decision tables](../decisions.md). This page tracks only
> the parts **not yet built**.

## Open items

- **Multiple `out` columns.** Today a table has a single `out` (a scalar result).
  Several outputs should synthesize a record `<Decision>Out { … }` (analogous to
  how user types get their shapes) so callers read `s.cost` / `s.express`. Needs
  program-level synthesis of the record type from the `out` declarations.

- **`hit unique`.** Every row is tested; exactly one must match, else a runtime
  panic naming the decision (a catch-all default is then illegal). Order-free.

- **`hit collect`** (+ aggregators). Return the outputs of *all* matching rows as
  a list; optional `sum | min | max | count` folds for a single numeric `out`.
  The row count is known at compile time, so a fixed-capacity buffer suffices.

- **Static completeness / overlap / dead-rule analysis.** The constrained cell
  DSL (everything except `?(…)`) is designed to allow a later checker that proves
  a table is total and non-overlapping; `?(…)` cells are exempt.

- **`priority` and `any` hit policies**, and **rule metadata** (per-row id /
  description, render-as-truth-table).

## Background

The shipped when-form and table-form share one lowering (an `if/return` chain
generalized over the cell DSL); see [Decision tables](../decisions.md), the
source of truth.
