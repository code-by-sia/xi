// Generic interfaces: a type-parametric interface (interface Box<T>) is
// monomorphized per concrete instantiation, injected and dispatched like any
// interface. Distinct instantiations are distinct interfaces.
// G1 proof: a generic interface instantiated, injected, and dispatched.
interface Box<T> {
    mapper get() -> T
}
class IntBox implements Box<Integer> {
    deps {}
    mapper get() -> Integer => 42
}
class StrBox implements Box<String> {
    deps {}
    mapper get() -> String => "hello"
}

// two consumers, each depending on a different instantiation
interface Runner { mapper run() -> Integer }
class IntRunner implements Runner {
    deps { b: Box<Integer> }
    mapper run() -> Integer => b.get()
}
interface Teller { mapper tell() -> String }
class StrTeller implements Teller {
    deps { b: Box<String> }
    mapper tell() -> String => b.get()
}

module App {
    bind Runner -> IntRunner as singleton
    bind Teller -> StrTeller as singleton
}

test "Box<Integer> resolves, injects, dispatches" {
    let r = App.resolve(Runner)
    assertEq(r.run(), 42)
}
test "Box<String> is a distinct instantiation" {
    let t = App.resolve(Teller)
    assertEq(t.tell(), "hello")
}
