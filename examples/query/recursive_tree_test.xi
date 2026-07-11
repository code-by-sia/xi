// Recursive sum types: variant payloads may reference the enclosing sum type
// directly (auto-boxed) or through containers (List<T>), so trees are ordinary
// values — constructed, matched, and serialized like anything else.
import "std/json.xi"

type Expr =
    | Lit  { value: Integer }
    | Bin  { op: String, left: Expr, right: Expr }
    | Call { name: String, args: List<Expr> }

mapper eval(e: Expr) -> Integer {
    match e {
        Lit l -> { return l.value }
        Bin b -> {
            if b.op == "+" { return eval(b.left) + eval(b.right) }
            if b.op == "*" { return eval(b.left) * eval(b.right) }
            return 0
        }
        Call c -> {
            let best = 0
            for a in c.args { let v = eval(a)  if v > best { best = v } }
            return best
        }
    }
    return 0
}

test "deeply nested tree evaluates" {
    // max(2*3, 4+1, 7) + (1+1) = 9
    let e = Bin { op: "+",
        left: Call { name: "max", args: listOf(
            Bin { op: "*", left: Lit { value: 2 }, right: Lit { value: 3 } },
            Bin { op: "+", left: Lit { value: 4 }, right: Lit { value: 1 } },
            Lit { value: 7 }) },
        right: Bin { op: "+", left: Lit { value: 1 }, right: Lit { value: 1 } } }
    assertEq(eval(e), 9)
}

test "a tree serializes to tagged JSON and round-trips" {
    let e = Bin { op: "*",
        left:  Call { name: "sum", args: listOf(Lit { value: 1 }, Lit { value: 2 }) },
        right: Lit { value: 10 } }
    let wire = json.stringify(e as Json)
    let back = (json.parse(wire)) as Expr
    assertEq(eval(back), eval(e))
}

test "unknown variant payload field is a compile-time concept (field access types)" {
    let e = Lit { value: 5 }
    match e {
        Lit l -> { assertEq(l.value, 5) }
        Bin b -> { assertEq(0, 1) }
        Call c -> { assertEq(0, 1) }
    }
}
