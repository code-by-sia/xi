// Feature: closures / lambdas + higher-order functions.
producer keep(xs: Integer[], p: (Integer) -> Bool) -> Integer {
    let n = 0
    for x in xs { if p(x) { n = n + 1 } }
    return n
}
mapper sumWith(xs: Integer[], f: (Integer) -> Integer) -> Integer {
    let s = 0
    for x in xs { s = s + f(x) }
    return s
}
// a local lambda binding is hoisted per function, so wrap it in a helper
mapper incOne(x: Integer) -> Integer {
    let inc = (n: Integer) => n + 1
    return inc(x)
}

test "local lambda binding" {
    assertEq(incOne(41), 42)
}
test "predicate lambda passed as an argument" {
    assertEq(keep([1, 2, 3, 4, 5], (n: Integer) => n > 3), 2)
}
test "mapping lambda accumulated in a loop" {
    assertEq(sumWith([1, 2, 3], (n: Integer) => n + 10), 36)   // 11+12+13
}
