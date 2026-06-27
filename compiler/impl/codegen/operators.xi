// xc codegen — operator-precedence chain (unary .. expr) + infix
// (part of the generator — spliced via the xc.xi manifest)

// ── unary ─────────────────────────────────────────────────────────
mapper genUnary(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let k = toks.kindAt(pos)
    if k == 119 {
        let r = genUnary(toks, pos + 1, ctx)
        return ExprRes { code: "(-" + r.code + ")", pos: r.pos, xtyp: r.xtyp , owned: false }
    }
    if k == 126 or k == 227 {
        let r = genUnary(toks, pos + 1, ctx)
        return ExprRes { code: "(!" + r.code + ")", pos: r.pos, xtyp: "Bool" , owned: false }
    }
    if k == 231 {
        // `await all <list>` — join every Future in a List<Future<T>>, return List<T>.
        if toks.kindAt(pos + 1) == 1 and toks.textAt(pos + 1) == "all" {
            let r = genUnary(toks, pos + 2, ctx)
            let elemX = listElemXName(r.xtyp)
            if isFutureXType(elemX) {
                let inC = futureInnerCtype(elemX)
                let u = int_to_string(pos)
                let code = "({ xc_List_t _af" + u + " = " + r.code + ";"
                         + " xc_List_t _ar" + u + " = xstd_list_new(sizeof(" + inC + "));"
                         + " for (xc_integer_t _ai" + u + " = 0; _ai" + u + " < xstd_list_len(_af" + u + "); _ai" + u + " = _ai" + u + " + 1) {"
                         + " xc_Future_t _fu" + u + " = *(xc_Future_t*)xstd_list_at(_af" + u + ", _ai" + u + ");"
                         + " " + inC + " _av" + u + " = *(" + inC + "*)xstd_future_await(_fu" + u + ");"
                         + " xstd_list_push(_ar" + u + ", &_av" + u + "); } _ar" + u + "; })"
                return ExprRes { code: code, pos: r.pos, xtyp: "List_" + futureInnerSuffix(elemX) , owned: false }
            }
            return r
        }
        // `await <future>` — block for the worker's result and yield the inner T.
        let r = genUnary(toks, pos + 1, ctx)
        if isFutureXType(r.xtyp) {
            let inC = futureInnerCtype(r.xtyp)
            return ExprRes { code: "(*(" + inC + "*)xstd_future_await(" + r.code + "))", pos: r.pos, xtyp: futureInnerXName(r.xtyp) , owned: false }
        }
        return r   // await on a non-future is a no-op (back-compat)
    }
    if k == 233 { return genUnary(toks, pos + 1, ctx) }
    if k == 251 { return genUnary(toks, pos + 1, ctx) }
    if k == 123 or k == 124 {
        let r = genUnary(toks, pos + 1, ctx)
        return ExprRes { code: "(&" + r.code + ")", pos: r.pos, xtyp: r.xtyp , owned: false }
    }
    return genPostfix(toks, pos, ctx)
}

// ── multiplicative ────────────────────────────────────────────────
mapper genMul(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genUnary(toks, pos, ctx)
    let code = left.code
    let typ = left.xtyp
    let p = left.pos
    let cont = true
    while cont {
        let k = toks.kindAt(p)
        if k == 120 or k == 121 or k == 122 {
            let op = " * "
            if k == 121 { op = " / " }
            if k == 122 { op = " % " }
            let right = genUnary(toks, p + 1, ctx)
            code = "(" + code + op + right.code + ")"
            typ = "Number"
            p = right.pos
        } else {
            cont = false
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: false }
}

// ── additive (with string concat) ────────────────────────────────
mapper genAdd(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genMul(toks, pos, ctx)
    let code = left.code
    let typ = left.xtyp
    let p = left.pos
    let resOwned = left.owned     // ARC: a concat result is freshly owned
    let cont = true
    while cont {
        let k = toks.kindAt(p)
        if k == 118 {
            let right = genMul(toks, p + 1, ctx)
            if typ == "String" or right.xtyp == "String" {
                code = "xc_string_concat(" + toStrC(code, typ) + ", " + toStrC(right.code, right.xtyp) + ")"
                typ = "String"
                resOwned = true
            } else {
                code = "(" + code + " + " + right.code + ")"
                resOwned = false
            }
            p = right.pos
        } else {
            if k == 119 {
                let right = genMul(toks, p + 1, ctx)
                code = "(" + code + " - " + right.code + ")"
                typ = "Number"
                resOwned = false
                p = right.pos
            } else {
                cont = false
            }
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: resOwned }
}

// ── integer ranges:  a..b (inclusive) / a until b / a downTo b / ... step n ──
mapper genRange(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genAdd(toks, pos, ctx)
    let p = left.pos
    let k = toks.kindAt(p)
    let isUntil  = (k == 1 and toks.textAt(p) == "until")
    let isDownTo = (k == 1 and toks.textAt(p) == "downTo")
    if k == 134 or isUntil or isDownTo {
        let right = genAdd(toks, p + 1, ctx)
        let endExpr = "(" + right.code + ") + 1"   // `..` inclusive
        let stepC = "1"
        if isUntil  { endExpr = "(" + right.code + ")" }
        if isDownTo { endExpr = "(" + right.code + ") - 1"  stepC = "-1" }
        let q = right.pos
        if toks.kindAt(q) == 1 and toks.textAt(q) == "step" {   // optional `step n`
            let se = genAdd(toks, q + 1, ctx)
            if isDownTo { stepC = "-(" + se.code + ")" } else { stepC = "(" + se.code + ")" }
            q = se.pos
        }
        return ExprRes {
            code: "(xc_range_t){ (" + left.code + "), " + endExpr + ", " + stepC + " }",
            pos: q, xtyp: "Range"
        , owned: false }
    }
    return left
}

// ── comparison ────────────────────────────────────────────────────
mapper genCmp(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genRange(toks, pos, ctx)
    let code = left.code
    let typ = left.xtyp
    let p = left.pos
    let cont = true
    while cont {
        let k = toks.kindAt(p)
        if k == 112 or k == 113 {
            let right = genAdd(toks, p + 1, ctx)
            if typ == "String" or right.xtyp == "String" {
                let eq = "xc_string_eq(" + code + ", " + right.code + ")"
                if k == 112 { code = eq } else { code = "(!" + eq + ")" }
            } else {
                let op = " == "
                if k == 113 { op = " != " }
                code = "(" + code + op + right.code + ")"
            }
            typ = "Bool"
            p = right.pos
        } else {
            if k == 114 or k == 115 or k == 116 or k == 117 {
                let op = " < "
                if k == 115 { op = " > " }
                if k == 116 { op = " <= " }
                if k == 117 { op = " >= " }
                let right = genAdd(toks, p + 1, ctx)
                code = "(" + code + op + right.code + ")"
                typ = "Bool"
                p = right.pos
            } else {
                if k == 252 {
                    let right = genAdd(toks, p + 1, ctx)
                    code = "xc_string_matches(" + code + ", " + right.code + ".data)"
                    typ = "Bool"
                    p = right.pos
                } else {
                    if k == 228 {
                        let right = genAdd(toks, p + 1, ctx)
                        code = "(1)"
                        typ = "Bool"
                        p = right.pos
                    } else {
                        cont = false
                    }
                }
            }
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: false }
}

// ── logical and / or ──────────────────────────────────────────────
mapper genAnd(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genCmp(toks, pos, ctx)
    let code = left.code
    let typ = left.xtyp
    let p = left.pos
    let cont = true
    while cont {
        if toks.kindAt(p) == 225 {
            let right = genCmp(toks, p + 1, ctx)
            code = "(" + code + " && " + right.code + ")"
            typ = "Bool"
            p = right.pos
        } else {
            cont = false
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: false }
}

mapper genExpr(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genAnd(toks, pos, ctx)
    let code = left.code
    let typ = left.xtyp
    let p = left.pos
    let cont = true
    while cont {
        if toks.kindAt(p) == 226 {
            let right = genAnd(toks, p + 1, ctx)
            code = "(" + code + " || " + right.code + ")"
            typ = "Bool"
            p = right.pos
        } else {
            cont = false
        }
    }
    // user `infix` functions: `a f b` -> f(a, b), left-associative (low precedence,
    // right operand at genAnd level so arithmetic binds tighter). Chains: a f b g c.
    let icont = true
    while icont {
        if toks.kindAt(p) == 1 and isInfixFnC(ctx.prog, toks.textAt(p)) {
            let fname = toks.textAt(p)
            let right = genAnd(toks, p + 1, ctx)
            code = "xc_" + fname + "(" + code + ", " + right.code + ")"
            typ = (ctx.prog).funcRetXType(fname)
            p = right.pos
        } else {
            icont = false
        }
    }
    // `a to b` — build a Pair<A,B> (low precedence, right of `||`). Bind both
    // sides to addressable temporaries (works for struct and scalar types alike).
    if toks.kindAt(p) == 1 and toks.textAt(p) == "to" {
        let right = genExpr(toks, p + 1, ctx)
        let lc = xnameToCtype(typ)
        let rc = xnameToCtype(right.xtyp)
        let u = int_to_string(p)
        let pcode = "({ " + lc + " _pa" + u + " = " + code + "; " + rc + " _pb" + u + " = " + right.code
                  + "; xc_pair_make(&_pa" + u + ", sizeof(" + lc + "), &_pb" + u + ", sizeof(" + rc + ")); })"
        return ExprRes { code: pcode, pos: right.pos, xtyp: pairXtype(typ, right.xtyp), owned: true }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: false }
}

predicate isInfixFnC(prog: Program, name: String) {
    return strArrContains(prog.infixFns, name)
}

