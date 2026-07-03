// Feature: module-scoped `const NAME: Type = expr`, referenced as Module.NAME
// from anywhere (free functions, class methods, other modules).

mapper clamp(n: Integer) -> Integer {
    if n > App.MAX { return App.MAX }
    return n
}

interface Greeter { projector hello() -> String }
class GreeterImpl implements Greeter {
    deps {}
    projector hello() -> String => App.GREETING + "!"
}

module App {
    const MAX: Integer      = 50
    const GREETING: String  = "hi"
    const DOUBLED: Integer   = 21 + 21
    bind Greeter -> GreeterImpl as singleton
}

test "const scalars and const-expressions" {
    assertEq(App.MAX, 50)
    assertEq(App.DOUBLED, 42)
}
test "const string" {
    assertEq(App.GREETING, "hi")
}
test "const used inside a free function" {
    assertEq(clamp(80), 50)
    assertEq(clamp(12), 12)
}
test "const used inside a class method" {
    let g = App.resolve(Greeter)
    assertEq(g.hello(), "hi!")
}
