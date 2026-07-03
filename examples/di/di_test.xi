// Feature: interfaces + classes + DI (module resolve) + self-method calls.
interface Adder {
    mapper add(a: Integer, b: Integer) -> Integer
    mapper addThree(a: Integer, b: Integer, c: Integer) -> Integer
}
class Calc implements Adder {
    deps {}
    mapper add(a: Integer, b: Integer) -> Integer { return a + b }
    mapper addThree(a: Integer, b: Integer, c: Integer) -> Integer { return add(add(a, b), c) }
}
module App { bind Adder -> Calc as singleton }

test "resolve from module and call method" {
    let calc = App.resolve(Adder)
    assertEq(calc.add(2, 3), 5)
}
test "self-method call inside a class" {
    let calc = App.resolve(Adder)
    assertEq(calc.addThree(1, 2, 3), 6)
}
