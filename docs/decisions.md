# Decision tables (DxT)

`decision` is a function kind for expressing business rules as a list of
`when <condition> => <result>` arms with a final `else`. It reads like a
decision table, and the conditions are ordinary Ξ expressions — so they can call
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

## How it lowers

```x
decision tier(s: Number) -> String {
    when s >= 700 => "high"
    else          => "low"
}
```

becomes, in effect:

```x
mapper tier(s: Number) -> String {
    if s >= 700 { return "high" }
    return "low"
}
```

## Dependency injection

Because a `decision` is a function kind, it can be an interface method, which
makes the whole *policy* injectable — swap one decision-backed implementation
for another without touching call sites.

```x
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

async entry main(args: String[]) -> Integer {
    let p = App.resolve(Pricing)              // auto-wired, decision-backed
    system.stdout.writeln("quote = " + p.quote(500, 100))
    return 0
}
module App {}
```

## Diagnostics

- An `else` arm is required (`decision requires an 'else' arm`).
- A `when` after `else` is rejected (it can never match).

## Beyond the when-form

The form above is single-input/single-output with `hit first` — close to a
guarded `match`. A proposed **tabular form** adds multiple input columns,
multiple outputs, and hit policies (`unique`, `collect`) to make decisions more
than `match`. See [the decision-tables proposal](proposals/decision-tables.md).

## Limitations (current)

- Only `hit first` is implemented. `unique` (exactly one arm may match) and
  other hit policies (`priority`, `collect`) are planned.
- Single output only.
- Arm results are expressions, not blocks.
- Because conditions are arbitrary expressions, the compiler does not yet prove
  completeness/overlap statically; that requires the finite-domain tabular form
  (a future addition).

See `examples/decision_demo.x`.
