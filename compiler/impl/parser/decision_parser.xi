// xc parser — decision tables (desugared to if/return)
// (part of the parser — spliced via the xc.xi manifest)

// Decision tables (DxT). Body grammar:
//     { [hit first] (when <expr> => <expr>)* else => <expr> }
// Desugars to ordinary body tokens — an if/return chain — so codegen is reused:
//     if <cond> { return <res> } ...  return <elseRes>
// Conditions and results are full expressions (may call predicates / use deps).
mapper parseDecisionBody(ps: PState) -> BodyResult {
    let out: Token[] = []
    let ps2 = ps
    if peek(ps2).kind != 102 { return BodyResult { bodyTokens: out, ps: ps2 } }  // {
    ps2 = advance(ps2)

    // optional `hit <policy>` (default: first; only first supported for now)
    if peek(ps2).kind == 257 {
        ps2 = advance(ps2)
        let pol = peek(ps2)
        if pol.text != "first" {
            diag_error(pol.line, "decision: only 'hit first' is supported (got '" + pol.text + "')")
        }
        ps2 = advance(ps2)
    }

    let hasElse = false
    let running = true
    while running {
        let t = peek(ps2)
        if t.kind == 103 or t.kind == 0 {
            running = false
        } else {
            if t.kind == 206 {                      // when <cond> => <res>
                if hasElse { diag_error(t.line, "decision: a 'when' after 'else' can never match") }
                ps2 = advance(ps2)
                // condition: collect until top-level `=>`
                let cond: Token[] = []
                let d = 0
                while running {
                    let c = peek(ps2)
                    if c.kind == 0 { diag_error(t.line, "decision: unterminated 'when' (missing =>)") running = false }
                    if d == 0 and c.kind == 110 { ps2 = advance(ps2) running = false } // => consumed
                    else {
                        if c.kind == 100 or c.kind == 104 { d = d + 1 }
                        if c.kind == 101 or c.kind == 105 { d = d - 1 }
                        cond = appendToken(cond, c)
                        ps2 = advance(ps2)
                    }
                }
                running = true
                // result: collect until top-level when / else / otherwise / }
                let res = collectArmResult(ps2)
                ps2 = res.ps
                out = appendToken(out, mkTok(222, "if", t.line))
                out = concatTokens(out, cond)
                out = appendToken(out, mkTok(102, "{", t.line))
                out = appendToken(out, mkTok(221, "return", t.line))
                out = concatTokens(out, res.bodyTokens)
                out = appendToken(out, mkTok(103, "}", t.line))
            } else {
                if t.kind == 223 or t.kind == 207 {  // else / otherwise => <res>
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 110 { ps2 = advance(ps2) }  // =>
                    let res = collectArmResult(ps2)
                    ps2 = res.ps
                    out = appendToken(out, mkTok(221, "return", t.line))
                    out = concatTokens(out, res.bodyTokens)
                    hasElse = true
                } else {
                    diag_error(t.line, "decision: expected 'when' or 'else', got '" + t.text + "'")
                    ps2 = advance(ps2)
                }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }
    if !hasElse { diag_error(peek(ps2).line, "decision requires an 'else' arm (the default outcome)") }
    return BodyResult { bodyTokens: out, ps: ps2 }
}

// Collect a decision arm's result expression: tokens up to a top-level
// `when` / `else` / `otherwise` / `}` (not consumed).
mapper collectArmResult(ps: PState) -> BodyResult {
    let res: Token[] = []
    let ps2 = ps
    let d = 0
    let going = true
    while going {
        let c = peek(ps2)
        if c.kind == 0 { going = false }
        else {
            if d == 0 and (c.kind == 206 or c.kind == 223 or c.kind == 207) { going = false }
            else {
                if d == 0 and c.kind == 103 { going = false }      // closing } of the table
                else {
                    if c.kind == 100 or c.kind == 104 or c.kind == 102 { d = d + 1 }
                    if c.kind == 101 or c.kind == 105 or c.kind == 103 { d = d - 1 }
                    res = appendToken(res, c)
                    ps2 = advance(ps2)
                }
            }
        }
    }
    return BodyResult { bodyTokens: res, ps: ps2 }
}

// ── decision table-form ──────────────────────────────────────────────────
// A grid `decision`: `in` columns become parameters, `out` columns the result
// (a scalar for one out, a synthesized `<Name>Out` record for several), each
// `| cell… => out… |` row a rule, with a hit policy (first / unique / collect
// [+ sum|min|max|count]) and the cell DSL. Table decisions are kept structurally
// (here) and emitted directly by codegen (genDecisionTables).

// One rule: the AND-of-cells condition tokens ([] = always), and the output
// expression tokens (one per out column, separated by `|` (kind 125)).
type DecisionRow = { cond: Token[], outs: Token[] }

type DecisionTable = {
    name:      String,
    params:    String,        // C params from `in`
    policy:    String,        // "first" | "unique" | "collect"
    agg:       String,        // "" | "sum" | "min" | "max" | "count"
    outNames:  String[],      // out column names (record field names when multi)
    outCtypes: String[],      // out column ctypes (parallel)
    retElem:   String,        // one row's value ctype: single out ctype, or xc_<Name>Out_t
    retCtype:  String,        // the decision's C return type (by policy/aggregator)
    isMulti:   Bool,          // more than one out -> record
    rows:      DecisionRow[]
}

// Result of parsing a `decision` body. For table-form, `table` is filled and (for
// multi-out) `outType` carries the synthesized record TypeSpec.
type DecisionResult = {
    bodyTokens: Token[], ps: PState, params: String, retCtype: String, isTable: Bool,
    table: DecisionTable, outType: TypeSpec, hasOutType: Bool
}
type RowResult = { cond: Token[], outs: Token[], ps: PState }

// Build a boolean test for one input cell, with `col` as the implicit subject.
// Returns synthesized tokens ([] = wildcard, contributes no condition).
mapper buildCellCond(colName: String, cell: Token[], line: Integer) -> Token[] {
    let out: Token[] = []
    let n = tokenArrLen(cell)
    if n == 0 { return out }
    let f0 = tokenArrGet(cell, 0)
    if n == 1 and f0.kind == 119 { return out }                 // '-' wildcard
    // comparison op first: col OP rest
    if f0.kind == 112 or f0.kind == 114 or f0.kind == 115 or f0.kind == 116 or f0.kind == 117 {
        out = appendToken(out, mkTok(1, colName, line))
        out = concatTokens(out, cell)
        return out
    }
    // not <test>
    if f0.kind == 227 {
        let rest: Token[] = []
        let k = 1
        while k < n { rest = appendToken(rest, tokenArrGet(cell, k)) k = k + 1 }
        out = appendToken(out, mkTok(227, "not", line))
        out = appendToken(out, mkTok(100, "(", line))
        out = concatTokens(out, buildCellCond(colName, rest, line))
        out = appendToken(out, mkTok(101, ")", line))
        return out
    }
    // [ lo .. hi ]  ->  ( col >= lo and col <= hi )   (inclusive range)
    if f0.kind == 104 {
        // split on the `..` (two consecutive '.') between '[' and ']'
        let lo: Token[] = []
        let hi: Token[] = []
        let inHi = false
        let i = 1
        while i < n {
            let it = tokenArrGet(cell, i)
            if it.kind == 105 { i = n }                                  // ]
            else {
                if it.kind == 134 {                                      // `..` (range token)
                    inHi = true
                    i = i + 1
                } else {
                if it.kind == 107 and i + 1 < n and tokenArrGet(cell, i + 1).kind == 107 {
                    inHi = true                                          // legacy: two `.` tokens
                    i = i + 2
                } else {
                    if inHi { hi = appendToken(hi, it) } else { lo = appendToken(lo, it) }
                    i = i + 1
                }
                }
            }
        }
        out = appendToken(out, mkTok(100, "(", line))
        out = appendToken(out, mkTok(1, colName, line))
        out = appendToken(out, mkTok(117, ">=", line))
        out = concatTokens(out, lo)
        out = appendToken(out, mkTok(225, "and", line))
        out = appendToken(out, mkTok(1, colName, line))
        out = appendToken(out, mkTok(116, "<=", line))
        out = concatTokens(out, hi)
        out = appendToken(out, mkTok(101, ")", line))
        return out
    }
    // in { a, b, ... }  ->  ( col == a or col == b ... )
    if f0.kind == 229 {
        out = appendToken(out, mkTok(100, "(", line))
        let i = 1
        if i < n and tokenArrGet(cell, i).kind == 102 { i = i + 1 }   // {
        let firstItem = true
        while i < n and tokenArrGet(cell, i).kind != 103 {
            let it = tokenArrGet(cell, i)
            if it.kind == 106 { i = i + 1 }                           // ,
            else {
                if not firstItem { out = appendToken(out, mkTok(226, "or", line)) }
                out = appendToken(out, mkTok(1, colName, line))
                out = appendToken(out, mkTok(112, "==", line))
                out = appendToken(out, it)
                firstItem = false
                i = i + 1
            }
        }
        out = appendToken(out, mkTok(101, ")", line))
        return out
    }
    // ?( expr )  -> the inner expression verbatim (escape hatch)
    if f0.kind == 127 {
        let i = 1
        if i < n and tokenArrGet(cell, i).kind == 100 { i = i + 1 }   // (
        while i < n and tokenArrGet(cell, i).kind != 101 {
            out = appendToken(out, tokenArrGet(cell, i))
            i = i + 1
        }
        return out
    }
    // bare literal/ident  ->  col == <cell>
    out = appendToken(out, mkTok(1, colName, line))
    out = appendToken(out, mkTok(112, "==", line))
    out = concatTokens(out, cell)
    return out
}

// Parse one `| c1 | c2 => out |` row into an if/return (or a default return).
// Parse one rule: AND-of-cells condition tokens, then `outCount` output exprs
// (kept with `|` separators between them so codegen can split).
mapper parseDecisionRow(ps: PState, inNames: String[], outCount: Integer) -> RowResult {
    let ps2 = ps
    let line = peek(ps2).line
    if peek(ps2).kind == 125 { ps2 = advance(ps2) }       // leading |
    let cond: Token[] = []
    let condStarted = false
    let ci = 0
    let nCols = stringArrLen(inNames)
    let collecting = true
    while collecting {
        let cell: Token[] = []
        let d = 0
        let cellDone = false
        while not cellDone {
            let c = peek(ps2)
            if c.kind == 0 { cellDone = true collecting = false }
            else {
                if d == 0 and (c.kind == 125 or c.kind == 110) { cellDone = true }
                else {
                    if c.kind == 100 or c.kind == 104 or c.kind == 102 { d = d + 1 }
                    if c.kind == 101 or c.kind == 105 or c.kind == 103 { d = d - 1 }
                    cell = appendToken(cell, c)
                    ps2 = advance(ps2)
                }
            }
        }
        if ci < nCols {
            let cc = buildCellCond(stringArrGet(inNames, ci), cell, line)
            if tokenArrLen(cc) > 0 {
                if condStarted { cond = appendToken(cond, mkTok(225, "and", line)) }
                cond = appendToken(cond, mkTok(100, "(", line))
                cond = concatTokens(cond, cc)
                cond = appendToken(cond, mkTok(101, ")", line))
                condStarted = true
            }
        }
        ci = ci + 1
        if peek(ps2).kind == 125 { ps2 = advance(ps2) }                 // | -> next cell
        else { if peek(ps2).kind == 110 { ps2 = advance(ps2) collecting = false }  // =>
               else { collecting = false } }
    }
    // outputs: outCount expressions, recorded with `|` separators between them
    let outs: Token[] = []
    let oi = 0
    while oi < outCount {
        if oi > 0 { outs = appendToken(outs, mkTok(125, "|", line)) }
        let d2 = 0
        let od = false
        while not od {
            let c = peek(ps2)
            if c.kind == 0 or c.kind == 103 { od = true }
            else {
                if d2 == 0 and c.kind == 125 { od = true }
                else {
                    if c.kind == 100 or c.kind == 104 or c.kind == 102 { d2 = d2 + 1 }
                    if c.kind == 101 or c.kind == 105 or c.kind == 103 { d2 = d2 - 1 }
                    outs = appendToken(outs, c)
                    ps2 = advance(ps2)
                }
            }
        }
        oi = oi + 1
        if peek(ps2).kind == 125 { ps2 = advance(ps2) }   // consume separator / trailing |
    }
    return RowResult { cond: cond, outs: outs, ps: ps2 }
}

// Dispatch a `decision` body: table-form (in/out grid) or the shipped when-form.
mapper parseDecision(name: String, ps: PState) -> DecisionResult {
    let emptyToks: Token[] = []
    let emptyStrs: String[] = []
    let emptyRows: DecisionRow[] = []
    let emptyTable = DecisionTable { name: "", params: "", policy: "first", agg: "", outNames: emptyStrs, outCtypes: emptyStrs, retElem: "", retCtype: "", isMulti: false, rows: emptyRows }
    let emptyType = TypeSpec { name: "", isCompound: false, baseCtype: "", fields: emptyStrs, hasWhere: false, whereSrc: "", whereTokens: emptyToks, isSum: false, variants: [] }
    // probe past `{` and an optional `hit <policy>` to detect the form
    let probe = 1
    if peekAt(ps, probe).kind == 257 { probe = probe + 2 }
    let det = peekAt(ps, probe)
    let isTable = det.kind == 229 or (det.kind == 1 and det.text == "out")
    if not isTable {
        let br = parseDecisionBody(ps)
        return DecisionResult { bodyTokens: br.bodyTokens, ps: br.ps, params: "", retCtype: "", isTable: false, table: emptyTable, outType: emptyType, hasOutType: false }
    }
    let ps2 = advance(ps)   // {
    let policy = "first"
    let agg = ""
    if peek(ps2).kind == 257 {                            // hit <policy> [agg]
        ps2 = advance(ps2)
        let pol = peek(ps2)
        if pol.text == "first" or pol.text == "unique" or pol.text == "collect" { policy = pol.text }
        else { diag_error(pol.line, "decision table: unknown hit policy '" + pol.text + "' (use first | unique | collect)") }
        ps2 = advance(ps2)
        if policy == "collect" {
            let a = peek(ps2)
            if a.kind == 1 and (a.text == "sum" or a.text == "min" or a.text == "max" or a.text == "count") {
                agg = a.text
                ps2 = advance(ps2)
            }
        }
    }
    let inNames: String[] = []
    let params = ""
    let outNames: String[] = []
    let outCtypes: String[] = []
    let cols = true
    while cols {
        let t = peek(ps2)
        if t.kind == 257 {                                             // hit <policy> [agg]
            ps2 = advance(ps2)
            let pol = peek(ps2)
            if pol.text == "first" or pol.text == "unique" or pol.text == "collect" { policy = pol.text }
            else { diag_error(pol.line, "decision table: unknown hit policy '" + pol.text + "' (use first | unique | collect)") }
            ps2 = advance(ps2)
            if policy == "collect" {
                let a = peek(ps2)
                if a.kind == 1 and (a.text == "sum" or a.text == "min" or a.text == "max" or a.text == "count") {
                    agg = a.text
                    ps2 = advance(ps2)
                }
            }
        }
        else {
        if t.kind == 229 {                                              // in name : Type
            ps2 = advance(ps2)
            let cn = peek(ps2).text
            ps2 = advance(ps2)
            if peek(ps2).kind == 108 { ps2 = advance(ps2) }
            let tr = parseTypeExpr(ps2)
            ps2 = tr.ps
            inNames = appendString(inNames, cn)
            if string_len(params) > 0 { params = params + ", " }
            params = params + tr.ctype + " " + cn
        } else {
        if t.kind == 1 and t.text == "out" {                            // out name : Type
            ps2 = advance(ps2)
            let on = peek(ps2).text
            ps2 = advance(ps2)
            if peek(ps2).kind == 108 { ps2 = advance(ps2) }
            let tr = parseTypeExpr(ps2)
            ps2 = tr.ps
            outNames = appendString(outNames, on)
            outCtypes = appendString(outCtypes, tr.ctype)
        } else { cols = false }
        }
        }
    }
    let outCount = stringArrLen(outNames)
    if outCount == 0 { diag_error(peek(ps2).line, "decision table: needs at least one 'out' column") }
    let isMulti = outCount > 1
    if isMulti and (agg == "sum" or agg == "min" or agg == "max") {
        diag_error(peek(ps2).line, "decision table: collect " + agg + " needs a single numeric 'out' column")
    }
    let retElem = ""
    let hasOutType = false
    let outType = emptyType
    if isMulti {
        let fields: String[] = []
        let fi = 0
        while fi < outCount {
            fields = appendString(fields, stringArrGet(outNames, fi) + ":" + stringArrGet(outCtypes, fi))
            fi = fi + 1
        }
        outType = TypeSpec { name: name + "Out", isCompound: true, baseCtype: "", fields: fields, hasWhere: false, whereSrc: "", whereTokens: emptyToks, isSum: false, variants: [] }
        hasOutType = true
        retElem = "xc_" + name + "Out_t"
    } else {
        retElem = stringArrGet(outCtypes, 0)
    }
    // function return type: by policy + aggregator
    let retCtype = retElem
    if policy == "collect" {
        if agg == "count" { retCtype = "xc_integer_t" }
        else { if agg == "sum" or agg == "min" or agg == "max" { retCtype = retElem }
               else { retCtype = "xc_arr_" + ctypeSuffix(retElem) + "_t" } }
    }
    // rows
    let rows: DecisionRow[] = []
    let more = true
    while more {
        if peek(ps2).kind == 125 {
            let rr = parseDecisionRow(ps2, inNames, outCount)
            ps2 = rr.ps
            rows = appendDecisionRow(rows, DecisionRow { cond: rr.cond, outs: rr.outs })
        } else { more = false }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }       // }
    let table = DecisionTable {
        name: name, params: params, policy: policy, agg: agg,
        outNames: outNames, outCtypes: outCtypes, retElem: retElem,
        retCtype: retCtype, isMulti: isMulti, rows: rows
    }
    return DecisionResult { bodyTokens: emptyToks, ps: ps2, params: params, retCtype: retCtype, isTable: true, table: table, outType: outType, hasOutType: hasOutType }
}

