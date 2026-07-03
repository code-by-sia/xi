// Feature: `capture` — bind a sub-expression's value (typed) and still yield it.
// `capture` is hoisted per function/method/entry, so exercise it inside helpers.
mapper foo(n: Integer) -> Integer { return n * 2 }
mapper bar(n: Integer) -> Integer { return n + 1 }
type Box = { v: Integer }
mapper    make(n: Integer) -> Box { return Box { v: n } }
predicate positive(b: Box) { return b.v > 0 }

mapper captureSum() -> Integer {
    let bigger = foo(10) capture a: Integer > bar(10) capture b: Integer
    if bigger { return a + b }    // a=20, b=11 -> 31
    return 0 - 1
}
mapper boxValue() -> Integer {
    if positive(make(7) capture box: Box) { return box.v }
    return 0 - 1
}

test "capture binds two reusable values mid-expression" {
    assertEq(captureSum(), 31)
}
test "capture a value from inside a call" {
    assertEq(boxValue(), 7)
}
