// Feature: extension functions on types — `mapper Type.method(...)` with `this`.
mapper Integer.double() -> Integer => this * 2
mapper Integer.plus(n: Integer) -> Integer { return this + n }
mapper String.shout() -> String { return this + "!" }
type Pt = { x: Integer, y: Integer }
mapper Pt.sum() -> Integer { return this.x + this.y }
predicate Pt.isOrigin() { return this.x == 0 and this.y == 0 }

test "extension on a primitive (Integer)" {
    let n: Integer = 21
    assertEq(n.double(), 42)
    assertEq(n.plus(9), 30)
}
test "extension on String" {
    let s = "hi"
    assertEq(s.shout(), "hi!")
}
test "extension on a user type" {
    let p = Pt { x: 3, y: 4 }
    assertEq(p.sum(), 7)
    assert not p.isOrigin()
    assert Pt { x: 0, y: 0 }.isOrigin()
}
test "chained extension calls" {
    let n: Integer = 5
    assertEq(n.double().plus(1), 11)
}
