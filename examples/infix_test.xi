// Feature: infix functions (callable `a f b`, left-associative).
infix mapper    plus(a: Integer, b: Integer) -> Integer { return a + b }
infix mapper    maxOf(a: Integer, b: Integer) -> Integer { if a > b { return a } return b }
infix predicate divides(a: Integer, b: Integer) { return b % a == 0 }

test "infix call and normal call agree" {
    assertEq(5 plus 3, 8)
    assertEq(plus(5, 3), 8)
}
test "left-associative chaining" {
    assertEq(2 plus 3 plus 4, 9)
}
test "infix max and predicate" {
    assertEq(7 maxOf 4, 7)
    assert 3 divides 12
    assert not (5 divides 12)
}
