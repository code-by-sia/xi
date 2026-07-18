import "std/convert.xi"

interface Counter { consumer bump()  projector count() -> Integer }
interface OtherView { projector peek() -> Integer }
interface Fresh { consumer bump()  projector count() -> Integer }

class SharedCounter implements Counter, OtherView {
    deps {}
    state { n: Integer = 0 }
    consumer bump() { this.n = this.n + 1 }
    projector count() -> Integer => this.n
    projector peek() -> Integer => this.n
}

class FreshCounter implements Fresh {
    deps {}
    state { n: Integer = 0 }
    consumer bump() { this.n = this.n + 1 }
    projector count() -> Integer => this.n
}

module App {
    scope = singleton                       // default for bare binds
    bind Counter   -> SharedCounter
    bind OtherView -> SharedCounter
    bind Fresh     -> FreshCounter as transient   // the exception
}

test "bare binds default to the module scope (singleton)" {
    let c = App.resolve(Counter)
    c.bump()
    c.bump()
    let v = App.resolve(OtherView)          // same singleton storage
    assertEq(v.peek(), 2)
    let c2 = App.resolve(Counter)           // resolves the same instance
    c2.bump()
    assertEq(v.peek(), 3)
}

test "an explicit `as transient` overrides the default" {
    let f1 = App.resolve(Fresh)
    f1.bump()
    f1.bump()
    let f2 = App.resolve(Fresh)             // fresh instance
    assertEq(f2.count(), 0)
    assertEq(f1.count(), 2)
}
