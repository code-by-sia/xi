// Using an atom through dependency injection: wrap the global atom in a class
// that implements an interface, so call sites depend on the interface (testable,
// decoupled) while the atom stays the implementation detail.
//
//   xc examples/atom_di_demo.xi && ./build/atom_di_demo
import "std/log.xi"
import "std/convert.xi"

state Counter = { n: Integer }

atom counter {
    initial Counter { n: 0 }
    transition inc(s: Counter) -> Counter { return Counter { n: s.n + 1 } }
}

interface CounterStore {
    consumer bump()
    producer value() -> Integer
}

// The atom is the implementation detail behind the interface.
class AtomCounterStore implements CounterStore {
    deps {}
    consumer bump()              { counter.inc() }
    producer value() -> Integer  { return counter.current.n }
}

async entry (logger: Logger, store: CounterStore) main(args: String[]) -> Integer {
    store.bump()
    store.bump()
    store.bump()
    logger.print("count = " + int_to_string(store.value()))   // 3
    return 0
}

module AtomDiDemo {}
