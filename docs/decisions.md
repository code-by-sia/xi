# Decision tables (DxT)

`decision` is a function kind for expressing business rules as a list of
`when <condition> => <result>` arms with a final `else`. It reads like a
decision table, and the conditions are ordinary Xi expressions — so they can call
`predicate` functions and use injected dependencies.

```x
decision creditTier(score: Number, income: Number) -> String {
    hit first
    when score >= 750                      => "gold"
    when score >= 650 and income >= 50000  => "gold"
    when score >= 650                      => "silver"
    else                                   => "bronze"
}
```

## Syntax

```
decision name(params) -> Type {
    [hit first]
    (when <boolean-expr> => <expr>)*
    else => <expr>
}
```

- **`hit first`** (the default; may be omitted) — the arms are evaluated top to
  bottom and the first matching arm's result is returned.
- **`when <cond> => <result>`** — `cond` is any boolean expression; `result` is
  any expression of the decision's return type.
- **`else => <result>`** — the mandatory default, evaluated when no `when`
  matches. It must come last.

A `decision` is just a value-returning function: it desugars to an `if/return`
chain, so it has the same performance as hand-written branches and can be called
like any other function.

## Dependency injection

Because a `decision` is a function kind, it can be an interface method, which
makes the whole *policy* injectable — swap one decision-backed implementation
for another without touching call sites.

```x
import "std/log.xi"

interface RiskModel { predicate risky(score: Number) }
class SimpleRisk implements RiskModel {
    deps {}
    predicate risky(s: Number) { return s < 600 }
}

interface Pricing { decision quote(score: Number, base: Number) -> Number }
class StdPricing implements Pricing {
    deps { risk: RiskModel }                  // injected into the decision
    decision quote(score: Number, base: Number) -> Number {
        hit first
        when risk.risky(score) => base * 2    // condition calls a dependency
        when score >= 700      => base * 0.9
        else                   => base
    }
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let p = App.resolve(Pricing)              // auto-wired, decision-backed
    logger.info("quote = " + p.quote(500, 100))
    return 0
}
module App {}
```

## Diagnostics

- An `else` arm is required (`decision requires an 'else' arm`).
- A `when` after `else` is rejected (it can never match).

## The tabular form

For genuinely multi-dimensional rules there is a **table form**: declare `in`
columns (which become the parameters) and one or more `out` columns (the result),
then write one rule per `| … => … |` row:

```x
decision shipping {
    in  weight: Number
    in  zone:   String
    out cost:   Number
    hit first

    //  weight        zone              => cost
    |   <= 1       | "US"               =>  5  |
    |   <= 1       | in {"CA", "MX"}    => 10  |
    |   [1 .. 5]   | -                  => 15  |
    |   > 5        | ?( zone == "US" )  => 30  |
    |   -          | -                  => 25  |   // default
}

let c = shipping(0.5, "US")     // 5
```

Each input **cell** is a unary test on its column:

| Cell | Means |
|------|-------|
| `-` | any (wildcard) |
| `42` / `"US"` | equals |
| `>= n`, `> n`, `<= n`, `< n` | comparison |
| `[a .. b]` | inclusive range |
| `in { a, b, c }` | membership |
| `not <test>` | negation |
| `?( <expr> )` | escape hatch: any boolean over the inputs (may call predicates) |

A row whose cells are all `-` is the default. The table compiles to a flat
`if/return` chain over the cells — zero runtime overhead — and, being a function
kind, a table `decision` is equally DI-injectable.

### Multiple outputs

List several `out` columns to return a **record**. The compiler synthesizes
`<Decision>Out` (e.g. `ShippingOut { cost, express }`); each row supplies one
expression per output, in order:

```x
decision shipping {
    in weight: Number   in zone: String
    out cost: Number    out express: Bool
    hit first
    |  <= 1     | "US"  =>  5 | true  |
    |  [1 .. 5] | -     => 15 | true  |
    |  -        | -     => 25 | false |
}
let s = shipping(3.0, "DE")     // s.cost == 15, s.express == true
```

### Hit policies

```
hit first     // top-to-bottom; the first matching row wins (the default)
hit unique    // exactly one row must match, else a runtime panic naming the table
hit collect   // every matching row contributes; returns a list of the outputs
```

`collect` may take an **aggregator** for a single numeric `out`:

```
hit collect sum | min | max     // fold the matching outputs -> one number
hit collect count               // how many rows matched -> Integer
```

```x
decision discount {
    in spend: Number
    out pct:   Number
    hit collect sum
    |  >= 100  => 5 |
    |  >= 500  => 5 |
    |  >= 1000 => 10 |
}
discount(1200.0)     // 5 + 5 + 10 = 20
```

Plain `collect` returns `<out>[]` (or `<Decision>Out[]` for several outs); the row
count is known at compile time, so it fills a fixed-capacity buffer.

## Limitations (current)

- Arm/output results are expressions, not blocks.
- Plain `collect` (no aggregator) over a single **numeric/bool** out needs the
  language's general primitive-array support; `String` outs and record (`<Decision>Out`)
  outs collect fine today.
- No static completeness/overlap analysis, `priority`/`any` policies, or per-rule
  metadata — these are deliberate non-goals for now (the `?( … )` escape hatch
  makes general static analysis undecidable anyway).

See `examples/language/decision_demo.xi` (when-form), `examples/language/decision_table_demo.xi`
(table form), and `examples/language/decision_table_advanced.xi` (multi-out, `unique`,
`collect`).
