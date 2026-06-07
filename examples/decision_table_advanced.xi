// Decision tables, full hit-policy set: multiple `out` columns (a synthesized
// record), `hit unique`, and `hit collect` with and without an aggregator.

// Several outputs -> a `<Decision>Out` record (here ShippingOut { cost, express }).
import "std/log.xi"
decision shipping {
    in  weight: Number
    in  zone:   String
    out cost:    Number
    out express: Bool
    hit first
    |  <= 1     | "US"            =>  5 | true  |
    |  [1 .. 5] | in {"US","CA"}  => 15 | true  |
    |  -        | -               => 25 | false |   // default
}

// `unique`: exactly one row must match (else a runtime panic).
decision grade {
    in score: Number
    out band:  String
    hit unique
    |  >= 90      => "A" |
    |  [70 .. 89] => "B" |
    |  < 70       => "C" |
}

// `collect` + aggregator: fold the matching rows' outputs.
decision discount {
    in spend: Number
    out pct:   Number
    hit collect sum
    |  >= 100  => 5 |
    |  >= 500  => 5 |
    |  >= 1000 => 10 |
}

// `collect` (no aggregator): the list of every matching row's output.
decision badges {
    in score: Number
    out badge: String
    hit collect
    |  >= 50 => "passing" |
    |  >= 90 => "honors" |
    |  < 60  => "at-risk" |
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let s = shipping(3.0, "CA")
    logger.print("shipping(3,CA): cost=" + s.cost + " express=" + s.express)   // 15 true

    logger.print("grade(95)=" + grade(95.0) + ", grade(72)=" + grade(72.0))    // A, B

    logger.print("discount(1200)=" + discount(1200.0) + "%")                    // 5+5+10 = 20

    let b = badges(95.0)                                                                 // passing + honors
    logger.print("badges(95): " + b.len + " ->")
    let i = 0
    while i < b.len { logger.print("  " + b.data[i]) i = i + 1 }
    return 0
}
