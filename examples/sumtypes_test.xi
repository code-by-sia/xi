// Feature: sum (algebraic) types + match with payload binding.
type Shape = | Circle { radius: Number } | Rect { w: Number, h: Number } | Empty
type Color = | Red | Green | Blue

mapper area(s: Shape) -> Number {
    match s {
        Circle c -> { return 3.0 * c.radius * c.radius }
        Rect r   -> { return r.w * r.h }
        Empty    -> { return 0.0 }
    }
    return 0.0
}
mapper label(c: Color) -> String {
    match c {
        Red   -> { return "red" }
        Green -> { return "green" }
        Blue  -> { return "blue" }
    }
    return "?"
}
test "sum type variant with payload" {
    assertClose(area(Circle { radius: 2.0 }), 12.0, 1e-9)
    assertClose(area(Rect { w: 3.0, h: 4.0 }), 12.0, 1e-9)
    assertClose(area(Empty), 0.0, 1e-9)
}
test "enum-like sum type" {
    assertEq(label(Red), "red")
    assertEq(label(Blue), "blue")
}
