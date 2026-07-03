// Unit tests for the eager List API — run with `xt examples/collections_test.xi`.

test "sum / contains / size" {
    let xs = listOf(3, 1, 4, 1, 5)
    assertEq(xs.sum(), 14)
    assert xs.contains(4)
    assert not xs.contains(9)
}

test "min / max" {
    let xs = listOf(3, 1, 4, 1, 5, 9, 2)
    assertEq(xs.min(), 1)
    assertEq(xs.max(), 9)
}

test "map and filter" {
    let xs = listOf(1, 2, 3, 4, 5, 6)
    let evens = xs.filter { x => x % 2 == 0 }
    assertEq(evens.sum(), 12)             // 2 + 4 + 6
    let doubled = xs.map { x => x * 2 }
    assertEq(doubled.sum(), 42)           // 2*(1+..+6) = 42
}
