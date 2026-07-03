// Decision table — the tabular form. `in` columns become parameters, the single
// `out` column is the result, and each `| … => … |` row is a rule. Cells are
// unary tests on their column (`hit first` returns the first matching row).
import "std/log.xi"
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

mapper line(w: Number, z: String) -> String {
    return "weight " + w + " to " + z + " => $" + shipping(w, z)
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.print(line(0.5, "US"))    // 5
    logger.print(line(0.5, "CA"))    // 10
    logger.print(line(3.0, "DE"))    // 15
    logger.print(line(9.0, "US"))    // 30 (escape-hatch cell)
    logger.print(line(9.0, "DE"))    // 25 (default)
    return 0
}
