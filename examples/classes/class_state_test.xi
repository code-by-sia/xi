// Feature: classes with a mutable `state { }` block — instance data read and
// written through `this.field`. A singleton keeps its state across calls.
interface Counter {
    consumer bump()
    consumer addN(n: Integer)
    projector count() -> Integer
}
class TallyCounter implements Counter {
    deps {}
    state { n: Integer = 0 }
    consumer bump()          { this.n = this.n + 1 }
    consumer addN(n: Integer) { this.n = this.n + n }
    projector count() -> Integer => this.n
}

interface Acc {
    consumer add(x: Number)
    projector total() -> Number
    projector label() -> String
}
class SumAcc implements Acc {
    deps {}
    state { sum: Number = 0.0, name: String = "acc" }
    consumer add(x: Number) { this.sum = this.sum + x }
    projector total() -> Number => this.sum
    projector label() -> String => this.name
}

module App {
    bind Counter -> TallyCounter as singleton
    bind Acc     -> SumAcc       as singleton
}

test "state accumulates across calls on a singleton" {
    let c = App.resolve(Counter)
    c.bump()
    c.bump()
    c.addN(5)
    assertEq(c.count(), 7)
}
test "typed state fields keep their initial values and update" {
    let a = App.resolve(Acc)
    assertEq(a.label(), "acc")     // String init
    a.add(1.5)
    a.add(2.5)
    assertClose(a.total(), 4.0, 1e-9)   // Number init + accumulation
}
