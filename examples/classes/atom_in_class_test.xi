// Feature: a class can drive a global `atom` from its methods. An atom is a
// managed, shared singleton (event-sourced state), so — unlike a machine value —
// it isn't held as per-instance `state`; the class references it by name and
// wraps it behind an interface (testable, decoupled).
state Counter = { n: Integer }

atom tally {
    initial Counter { n: 0 }
    transition inc(s: Counter) -> Counter          { return Counter { n: s.n + 1 } }
    transition add(s: Counter, k: Integer) -> Counter { return Counter { n: s.n + k } }
}

interface Tally {
    consumer bump()
    consumer addN(n: Integer)
    producer total() -> Integer
}
class TallyStore implements Tally {
    deps {}
    consumer bump()           { tally.inc() }
    consumer addN(n: Integer) { tally.add(n) }
    producer total() -> Integer { return tally.current.n }
}
module App { bind Tally -> TallyStore as singleton }

test "a class drives a global atom through its methods" {
    let t = App.resolve(Tally)
    t.bump()
    t.bump()
    t.addN(5)
    assertEq(t.total(), 7)
}
