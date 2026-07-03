// Feature: Result types (T!), ok/err, `?` propagation, isOk/isErr/.value/.err.
type Age = Number where value >= 0 and value <= 130

mapper checkAge(n: Number) -> Age! {
    if n < 0   { return err("negative") }
    if n > 130 { return err("too large") }
    return ok(n)
}
mapper classify(n: Number) -> String! {
    let a = checkAge(n)?            // `?` propagates the err
    if a < 18 { return ok("minor") }
    return ok("adult")
}
test "ok path" {
    let r = classify(25)
    assert isOk(r)
    assertEq(r.value, "adult")
}
test "err path via ? propagation" {
    let r = classify(0 - 5)
    assert isErr(r)
    assertEq(r.err, "negative")
}
test "assertOk / assertErr helpers" {
    assertOk(classify(10))
    assertErr(classify(200))
}
