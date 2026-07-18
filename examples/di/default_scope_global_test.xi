// `scope = singleton` is the program-wide default: it covers interfaces that are
// auto-resolved (never named in a `bind`), not just the module's bind lines.
interface Registry { consumer add()  projector size() -> Integer }
interface Audit    { consumer note()  projector notes() -> Integer }
interface Fresh    { consumer add()  projector size() -> Integer }

class MemRegistry implements Registry {          // no bind anywhere
    deps {}
    state { n: Integer = 0 }
    consumer add() { this.n = this.n + 1 }
    projector size() -> Integer => this.n
}
class MemAudit implements Audit {                // injected, never bound
    deps {}
    state { n: Integer = 0 }
    consumer note() { this.n = this.n + 1 }
    projector notes() -> Integer => this.n
}
class MemFresh implements Fresh {
    deps {}
    state { n: Integer = 0 }
    consumer add() { this.n = this.n + 1 }
    projector size() -> Integer => this.n
}

// A consumer that receives Audit by injection (no bind line for Audit).
interface Service { consumer touch()  projector seen() -> Integer }
class SvcImpl implements Service {
    deps { audit: Audit }
    consumer touch() { audit.note() }
    projector seen() -> Integer => audit.notes()
}

module App {
    scope = singleton                 // default for the whole program
    bind Fresh -> MemFresh as transient   // exception still wins
}

test "auto-resolved interface (no bind) follows the module default" {
    let r1 = App.resolve(Registry)
    r1.add()
    r1.add()
    let r2 = App.resolve(Registry)     // same instance, no bind line needed
    assertEq(r2.size(), 2)
}

test "an injected dep shares the same singleton as a direct resolve" {
    let svc = App.resolve(Service)
    svc.touch()
    let a = App.resolve(Audit)         // the very instance injected into SvcImpl
    assertEq(a.notes(), 1)
    a.note()
    assertEq(svc.seen(), 2)
}

test "`as transient` still overrides the default" {
    let f1 = App.resolve(Fresh)
    f1.add()
    let f2 = App.resolve(Fresh)
    assertEq(f2.size(), 0)
    assertEq(f1.size(), 1)
}
