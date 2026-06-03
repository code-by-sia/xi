// Decision tables (DxT) — the `decision` function kind.
//
// A decision lists `when <condition> => <result>` arms with a final `else`.
// Conditions are ordinary expressions (they may call predicates or injected
// dependencies). `hit first` (the default) returns the first matching arm.

// Standalone decision.
decision creditTier(score: Number, income: Number) -> String {
    hit first
    when score >= 750                      => "gold"
    when score >= 650 and income >= 50000  => "gold"
    when score >= 650                      => "silver"
    else                                   => "bronze"
}

// A predicate, reused as a decision condition.
predicate isVip(score: Number) { return score >= 900 }

// Decisions work through DI: a decision can implement an interface method,
// and its conditions can use injected dependencies.
interface RiskModel { predicate risky(score: Number) }
class SimpleRisk implements RiskModel {
    deps {}
    predicate risky(s: Number) { return s < 600 }
}

interface Pricing { decision quote(score: Number, base: Number) -> Number }
class StdPricing implements Pricing {
    deps { risk: RiskModel }
    decision quote(score: Number, base: Number) -> Number {
        hit first
        when risk.risky(score)  => base * 2
        when isVip(score)       => base * 0.5
        when score >= 700       => base * 0.9
        else                    => base
    }
}

async entry main(args: String[]) -> Integer {
    system.stdout.writeln("tier 800/0     = " + creditTier(800, 0))
    system.stdout.writeln("tier 700/60000 = " + creditTier(700, 60000))
    system.stdout.writeln("tier 700/10000 = " + creditTier(700, 10000))
    system.stdout.writeln("tier 500/0     = " + creditTier(500, 0))

    let p = App.resolve(Pricing)
    system.stdout.writeln("quote risky    = " + p.quote(500, 100))
    system.stdout.writeln("quote vip      = " + p.quote(950, 100))
    system.stdout.writeln("quote good     = " + p.quote(750, 100))
    system.stdout.writeln("quote base     = " + p.quote(650, 100))
    return 0
}

module App {}
