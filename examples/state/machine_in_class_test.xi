// Feature: a class can hold a `machine` value in its mutable state and drive it.
// Machines are immutable value types, so a state field holds one and each
// transition reassigns this.<field> with the returned next-state value.
machine Turnstile {
    states  Locked, Open
    initial Locked
    terminal -
    coin : Locked -> Open
    push : Open   -> Locked
}

interface Gate {
    consumer insertCoin()
    consumer pushThrough()
    projector state() -> String
}
class GateImpl implements Gate {
    deps {}
    state { t: Turnstile = Turnstile.start() }
    consumer insertCoin()  { this.t = this.t.coin() }
    consumer pushThrough() { this.t = this.t.push() }
    projector state() -> String => this.t.state
}
module App { bind Gate -> GateImpl as singleton }

test "a class holds a machine and drives its transitions" {
    let g = App.resolve(Gate)
    assertEq(g.state(), "Locked")    // machine's initial state
    g.insertCoin()
    assertEq(g.state(), "Open")
    g.pushThrough()
    assertEq(g.state(), "Locked")
}
