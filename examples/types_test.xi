// Feature: compound types, refined types, type aliases, optionals, inline bodies.
type Age      = Number where value >= 0 and value <= 130
type NonEmpty = String where value.length > 0
type Person   = { name: NonEmpty, age: Age }
type People   = Person[]

mapper square(n: Integer) -> Integer => n * n   // inline body
mapper noneOf() -> Integer? { return none }     // optional: the none case
// if-let on an optional is exercised inside a function (hoisted there)
mapper minOrZero(xs: Integer[]) -> Integer {
    if let m = listOf(xs.data[0], xs.data[1], xs.data[2]).minOrNone() { return m }
    return 0
}

test "compound type construction + field access" {
    let p = Person { name: "Ada", age: 36 }
    assertEq(p.name, "Ada")
    assertEq(p.age, 36)
}
test "refined type accepts boundary values" {
    let p = Person { name: "Bob", age: 0 }
    assertEq(p.age, 0)
}
test "array alias + .len" {
    let ps: People = [Person { name: "A", age: 1 }, Person { name: "B", age: 2 }]
    assertEq(ps.len, 2)
}
test "optional none does not unwrap" {
    if let v = noneOf() { assert false : "expected none" }
}
test "optional some unwraps (minOrNone in a function)" {
    assertEq(minOrZero([5, 2, 8]), 2)
}
test "inline function body (=>)" {
    assertEq(square(7), 49)
}
