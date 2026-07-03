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

// extensions also work on array types: `Type[].method`, with `this` the array.
mapper Integer[].total() -> Integer {
    let s = 0
    let i = 0
    while i < this.len { s = s + this.data[i]  i = i + 1 }
    return s
}

test "extension on an array type (param + literal-var)" {
    let xs: Integer[] = [3, 4, 5]
    assertEq(xs.total(), 12)
    assertEq([10, 20, 30].total(), 60)
}
