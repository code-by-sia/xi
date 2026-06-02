// Error handling with Result (`T!`), ok/err, and `?` propagation.

type Age = Number where value >= 0 and value <= 130

// Returns a Result<Age> (string error).
mapper checkAge(n: Number) -> Age! {
    if n < 0   { return err("age is negative") }
    if n > 130 { return err("age too large") }
    return ok(n)
}

// `?` propagates the Err from checkAge; otherwise unwraps the Age.
mapper classify(n: Number) -> String! {
    let a = checkAge(n)?
    if a < 18 { return ok("minor") }
    return ok("adult")
}

consumer report(label: String, r: String!) {
    if isOk(r) {
        system.stdout.writeln(label + " -> " + r.value)
    } else {
        system.stdout.writeln(label + " -> error: " + r.err)
    }
}

async entry main(args: String[]) -> Integer {
    report("25",  classify(25))
    report("10",  classify(10))
    report("200", classify(200))
    report("-5",  classify(-5))
    return 0
}
