// Unit tests — run with `xi test examples/calc_test.xi`.
//
// A `test "name" { ... }` case asserts with `assert <expr>`; a failed assert
// reports the expression + file:line and aborts just that test. Tests can take
// injected deps `(dep: I)`, and `module Test` supplies test doubles (layered
// over `module App`, ignored in normal builds).

mapper add(a: Integer, b: Integer) -> Integer { return a + b }
mapper mul(a: Integer, b: Integer) -> Integer { return a * b }

interface Clock { mapper now() -> Integer }
class RealClock implements Clock { deps {} mapper now() -> Integer { return 9999 } }
class FakeClock implements Clock { deps {} mapper now() -> Integer { return 44 } }

test "addition" {
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
}

test "multiplication" {
    assert mul(4, 5) == 20
    assert mul(0, 9) == 0
}

test "uses the test double for Clock" (clock: Clock) {
    assert clock.now() == 44        // FakeClock from `module Test`, not RealClock
}

module Test { bind Clock -> FakeClock }
module App  { bind Clock -> RealClock }
