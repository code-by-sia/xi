// Value-showing assertions. Run with:  xi test examples/asserts_test.xi
import "std/convert.xi"

mapper add(a: Integer, b: Integer) -> Integer { return a + b }
mapper half(x: Number) -> Number { return x / 2.0 }

mapper parseAge(s: String) -> Integer! {
    if s == "" { return err("empty input") }
    return ok(30)
}

test "assertEq / assertNe report values" {
    assertEq(add(2, 3), 5)
    assertNe(add(2, 3), 6)
    assertEq("ab" + "c", "abc")          // Strings compared by content
}

test "assertClose tolerates float error" {
    assertClose(half(1.0), 0.5, 1e-9)
    assertClose(0.1 + 0.2, 0.3, 1e-9)    // would fail with plain ==
}

test "error paths with assertOk / assertErr" {
    assertOk(parseAge("44"))
    assertErr(parseAge(""))
}

test "assert with a message" {
    assert add(2, 2) == 4 : "addition must hold"
}
