// xc codegen — xi-query: reify a query chain into a QueryPlan value.
// (part of the xc code generator — Program -> C99; spliced via xc.xi)
//
// `query.from<T>("source")` seeds a plan (xtype "Query_<T>"); each chained
// stage — filter / map / sortedBy / take / drop / concat — appends a
// QueryStage to the plan instead of compiling to a loop; `collect(provider)`
// hands the finished plan to the provider and decodes the returned rows into
// a List of the chain's element type. The plan/stage/expression types live in
// std/query.xi; the lambda bodies are reified into QueryExpr constructor
// values, so a provider receives the query as a typed tree it can translate.
//
// Scope rule inside a reified lambda: the lambda parameter becomes QField
// references; any other name from the enclosing scope is evaluated NOW and
// embedded as a QParam value — so plans never capture live locals.

type QRes = { code: String, pos: Integer, xtyp: String }

// ── QueryExpr constructor emitters ─────────────────────────────────
mapper qNodeC(variant: String, body: String) -> String {
    return "(xc_QueryExpr_t){ .tag = xc_QueryExpr_" + variant + ", .u." + variant + " = { " + body + " } }"
}
mapper qLitC(jsonExpr: String) -> String => qNodeC("QLit", ".value = " + jsonExpr)
mapper qParamC(jsonExpr: String) -> String => qNodeC("QParam", ".value = " + jsonExpr)
mapper qFieldC(path: String) -> String => qNodeC("QField", ".path = xc_string_from_cstr(\"" + path + "\")")
mapper qBinC(op: String, l: String, r: String) -> String {
    return qNodeC("QBin", ".op = xc_string_from_cstr(\"" + op + "\"), .left = xc_box_QueryExpr(" + l + "), .right = xc_box_QueryExpr(" + r + ")")
}
mapper qUnC(op: String, x: String) -> String {
    return qNodeC("QUn", ".op = xc_string_from_cstr(\"" + op + "\"), .operand = xc_box_QueryExpr(" + x + ")")
}
// The op text for a comparison/arithmetic token kind ("" = not an op).
mapper qCmpOp(k: Integer) -> String {
    if k == 112 { return "==" }
    if k == 113 { return "!=" }
    if k == 114 { return "<" }
    if k == 115 { return ">" }
    if k == 116 { return "<=" }
    if k == 117 { return ">=" }
    if k == 252 { return "matches" }
    if k == 229 { return "in" }
    return ""
}

// Whitelisted methods a reified expression may call — the shape the plan can
// carry. Whether a given provider can translate them is the provider's call.
mapper qMethodRet(m: String) -> String {
    if m == "contains" or m == "startsWith" or m == "endsWith" { return "Bool" }
    if m == "lowercase" or m == "uppercase" { return "String" }
    if m == "length" { return "Integer" }
    return ""
}

// ── the expression reifier (precedence climbing) ──────────────────
mapper qreifyExpr(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    return qreifyOr(toks, pos, ctx, prm, elem)
}

mapper qreifyOr(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let l = qreifyAnd(toks, pos, ctx, prm, elem)
    while toks.kindAt(l.pos) == 226 {                       // or
        let r = qreifyAnd(toks, l.pos + 1, ctx, prm, elem)
        l = QRes { code: qBinC("or", l.code, r.code), pos: r.pos, xtyp: "Bool" }
    }
    return l
}

mapper qreifyAnd(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let l = qreifyNot(toks, pos, ctx, prm, elem)
    while toks.kindAt(l.pos) == 225 {                       // and
        let r = qreifyNot(toks, l.pos + 1, ctx, prm, elem)
        l = QRes { code: qBinC("and", l.code, r.code), pos: r.pos, xtyp: "Bool" }
    }
    return l
}

mapper qreifyNot(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    if toks.kindAt(pos) == 227 {                            // not
        let x = qreifyNot(toks, pos + 1, ctx, prm, elem)
        return QRes { code: qUnC("not", x.code), pos: x.pos, xtyp: "Bool" }
    }
    return qreifyCmp(toks, pos, ctx, prm, elem)
}

mapper qreifyCmp(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let l = qreifyAdd(toks, pos, ctx, prm, elem)
    let op = qCmpOp(toks.kindAt(l.pos))
    if string_len(op) > 0 {
        let r = qreifyAdd(toks, l.pos + 1, ctx, prm, elem)
        return QRes { code: qBinC(op, l.code, r.code), pos: r.pos, xtyp: "Bool" }
    }
    return l
}

mapper qreifyAdd(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let l = qreifyMul(toks, pos, ctx, prm, elem)
    let going = true
    while going {
        let k = toks.kindAt(l.pos)
        if k == 118 {
            let r = qreifyMul(toks, l.pos + 1, ctx, prm, elem)
            l = QRes { code: qBinC("+", l.code, r.code), pos: r.pos, xtyp: l.xtyp }
        } else { if k == 119 {
            let r = qreifyMul(toks, l.pos + 1, ctx, prm, elem)
            l = QRes { code: qBinC("-", l.code, r.code), pos: r.pos, xtyp: l.xtyp }
        } else { going = false } }
    }
    return l
}

mapper qreifyMul(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let l = qreifyUnary(toks, pos, ctx, prm, elem)
    let going = true
    while going {
        let k = toks.kindAt(l.pos)
        let op = ""
        if k == 120 { op = "*" }
        if k == 121 { op = "/" }
        if k == 122 { op = "%" }
        if string_len(op) > 0 {
            let r = qreifyUnary(toks, l.pos + 1, ctx, prm, elem)
            l = QRes { code: qBinC(op, l.code, r.code), pos: r.pos, xtyp: l.xtyp }
        } else { going = false }
    }
    return l
}

mapper qreifyUnary(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    if toks.kindAt(pos) == 119 {                            // unary minus
        let x = qreifyUnary(toks, pos + 1, ctx, prm, elem)
        return QRes { code: qUnC("-", x.code), pos: x.pos, xtyp: x.xtyp }
    }
    return qreifyAtom(toks, pos, ctx, prm, elem)
}

// Build the C for one reified call-argument list: List<QueryExpr>.
mapper qArgsListC(toks: Token[], pos0: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    // pos0 is just after '('; reify comma-separated args until ')'.
    let u = int_to_string(pos0)
    let build = "({ xc_List_t __qa" + u + " = xstd_list_new(sizeof(xc_QueryExpr_t)); "
    let p = pos0
    while toks.kindAt(p) != 101 and toks.kindAt(p) != 0 {
        let a = qreifyExpr(toks, p, ctx, prm, elem)
        build = build + "xstd_list_push(__qa" + u + ", (xc_QueryExpr_t[]){ " + a.code + " }); "
        p = a.pos
        if toks.kindAt(p) == 106 { p = p + 1 }
    }
    if toks.kindAt(p) == 101 { p = p + 1 }
    return QRes { code: build + "__qa" + u + "; })", pos: p, xtyp: "" }
}

// Method calls chained onto a reified receiver (field/param roots).
mapper qreifyCalls(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String, recv0: String, xt0: String) -> QRes {
    let recv = recv0
    let xt = xt0
    let p = pos
    while toks.kindAt(p) == 107 and toks.kindAt(p + 2) == 100 {
        let m = toks.textAt(p + 1)
        let ret = qMethodRet(m)
        if string_len(ret) == 0 {
            diag_error(tokenArrGet(toks, p + 1).line, "xi-query: '" + m + "(...)' can't appear in a query expression — supported methods: contains, startsWith, endsWith, lowercase, uppercase, length")
        }
        let args = qArgsListC(toks, p + 3, ctx, prm, elem)
        recv = qNodeC("QCall", ".method = xc_string_from_cstr(\"" + m + "\"), .recv = xc_box_QueryExpr(" + recv + "), .args = " + args.code)
        xt = ret
        p = args.pos
    }
    return QRes { code: recv, pos: p, xtyp: xt }
}

mapper qreifyAtom(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let t = tokenArrGet(toks, pos)
    if t.kind == 2 {                                        // integer literal
        return QRes { code: qLitC("xstd_json_number((xc_number_t)" + t.text + ")"), pos: pos + 1, xtyp: "Integer" }
    }
    if t.kind == 3 {                                        // float literal
        return QRes { code: qLitC("xstd_json_number(" + t.text + ")"), pos: pos + 1, xtyp: "Number" }
    }
    if t.kind == 4 {                                        // string literal
        return QRes { code: qLitC("xstd_json_string(xc_string_from_cstr(\"" + t.text + "\"))"), pos: pos + 1, xtyp: "String" }
    }
    if t.kind == 236 { return QRes { code: qLitC("xstd_json_bool(1)"), pos: pos + 1, xtyp: "Bool" } }
    if t.kind == 237 { return QRes { code: qLitC("xstd_json_bool(0)"), pos: pos + 1, xtyp: "Bool" } }
    if t.kind == 100 {                                      // ( expr )
        let inner = qreifyExpr(toks, pos + 1, ctx, prm, elem)
        let p = inner.pos
        if toks.kindAt(p) == 101 { p = p + 1 }
        return QRes { code: inner.code, pos: p, xtyp: inner.xtyp }
    }
    if t.kind == 1 and t.text == prm {
        // group element: it.key / it.count() / it.sum { x => ... } / avg / min / max
        if elem.startsWith2("qgroup:") {
            return qreifyGroupIt(toks, pos, ctx, prm, elem)
        }
        // the lambda parameter: a field path rooted at the row. On a joined
        // element (qpair:<L>:<R>) the first hop picks the side.
        let path = ""
        let xt = elem
        let p = pos + 1
        if elem.startsWith2("qpair:") and toks.kindAt(p) == 107 {
            let rest = string_slice(elem, 6, string_len(elem))
            let cpos = findChar(rest, 58)
            let side = toks.textAt(p + 1)
            if side == "first" {
                path = "first"
                xt = string_slice(rest, 0, cpos)
                p = p + 2
            } else { if side == "second" {
                path = "second"
                xt = string_slice(rest, cpos + 1, string_len(rest))
                p = p + 2
            } else {
                diag_error(tokenArrGet(toks, p + 1).line, "xi-query: a joined row is a pair — address its sides as it.first / it.second")
            } }
        }
        let walking = true
        while walking and toks.kindAt(p) == 107 and toks.kindAt(p + 2) != 100 {
            let fld = toks.textAt(p + 1)
            if (ctx.prog).isCompoundTypeC(xt) and not (ctx.prog).hasFieldC(xt, fld) {
                diag_error(tokenArrGet(toks, p + 1).line, "type '" + xt + "' has no field '" + fld + "'")
            }
            let nxt = (ctx.prog).fieldTypeNameC(xt, fld)
            if string_len(path) == 0 { path = fld } else { path = path + "." + fld }
            xt = nxt
            p = p + 2
            // stop extending the path when the next hop is a method call
            if toks.kindAt(p) == 107 and toks.kindAt(p + 2) == 100 { walking = false }
        }
        return qreifyCalls(toks, p, ctx, prm, elem, qFieldC(path), xt)
    }
    if t.kind == 1 and (ctx.prog).isCompoundTypeC(t.text) and toks.kindAt(pos + 1) == 102 {
        // record projection:  TypeName { field: expr, ... }  -> QRecord
        let tname = t.text
        let u = int_to_string(pos)
        let names = "({ xc_List_t __qrn" + u + " = xstd_list_new(sizeof(xc_string_t)); "
        let exprs = "({ xc_List_t __qre" + u + " = xstd_list_new(sizeof(xc_QueryExpr_t)); "
        let p = pos + 2
        while toks.kindAt(p) != 103 and toks.kindAt(p) != 0 {
            let fname = toks.textAt(p)
            if not (ctx.prog).hasFieldC(tname, fname) {
                diag_error(tokenArrGet(toks, p).line, "type '" + tname + "' has no field '" + fname + "'")
            }
            p = p + 1
            if toks.kindAt(p) == 108 { p = p + 1 }               // :
            let fe = qreifyExpr(toks, p, ctx, prm, elem)
            names = names + "xstd_list_push(__qrn" + u + ", (xc_string_t[]){ xc_string_from_cstr(\"" + fname + "\") }); "
            exprs = exprs + "xstd_list_push(__qre" + u + ", (xc_QueryExpr_t[]){ " + fe.code + " }); "
            p = fe.pos
            if toks.kindAt(p) == 106 { p = p + 1 }               // ,
        }
        if toks.kindAt(p) == 103 { p = p + 1 }                   // }
        let rec = qNodeC("QRecord", ".names = " + names + "__qrn" + u + "; }), .exprs = " + exprs + "__qre" + u + "; })")
        return QRes { code: rec, pos: p, xtyp: tname }
    }
    if t.kind == 1 {
        // any other name: an enclosing local — evaluate now, embed as QParam.
        let xt = ctx.lookupVar(t.text)
        if string_len(xt) == 0 {
            diag_error(t.line, "xi-query: unknown name '" + t.text + "' in a query expression — only the lambda parameter and enclosing locals can appear")
        }
        let acc = t.text
        let p = pos + 1
        // member access on a captured value is evaluated at build time
        while toks.kindAt(p) == 107 and toks.kindAt(p + 2) != 100 {
            let fld = toks.textAt(p + 1)
            if (ctx.prog).isCompoundTypeC(xt) and not (ctx.prog).hasFieldC(xt, fld) {
                diag_error(tokenArrGet(toks, p + 1).line, "type '" + xt + "' has no field '" + fld + "'")
            }
            acc = acc + "." + fld
            xt = (ctx.prog).fieldTypeNameC(xt, fld)
            p = p + 2
        }
        let enc = ""
        if xt.isListXType() or xt.startsWith2("arr_") {
            enc = jsonOfPayload(ctx.prog, xt, acc)
        } else {
            enc = jsonEncodeExpr(ctx.prog, xt.xnameToCtype(), acc)
        }
        if string_len(enc) == 0 {
            diag_error(t.line, "xi-query: can't embed '" + t.text + "' (type " + xt + ") into a query plan")
        }
        return qreifyCalls(toks, p, ctx, prm, elem, qParamC(enc), xt)
    }
    diag_error(t.line, "xi-query: unsupported expression in a query lambda (near '" + t.text + "')")
    return QRes { code: "", pos: pos + 1, xtyp: "" }
}

// Reify `it` on a grouped element ("qgroup:<Elem>:<KeyXtype>"): the key or an
// aggregate over the group's rows.
mapper qreifyGroupIt(toks: Token[], pos: Integer, ctx: GCtx, prm: String, elem: String) -> QRes {
    let rest = string_slice(elem, 7, string_len(elem))
    let lastColon = 0 - 1
    let ci = 0
    while ci < string_len(rest) {
        if string_char_at(rest, ci) == 58 { lastColon = ci }
        ci = ci + 1
    }
    let inner = string_slice(rest, 0, lastColon)
    let keyX = string_slice(rest, lastColon + 1, string_len(rest))
    let p = pos + 1
    if toks.kindAt(p) != 107 {
        diag_error(tokenArrGet(toks, pos).line, "xi-query: a grouped row is addressed as it.key or an aggregate — it.count(), it.sum { ... }, it.avg { ... }, it.min { ... }, it.max { ... }")
    }
    let name = toks.textAt(p + 1)
    if name == "key" {
        return qreifyCalls(toks, p + 2, ctx, prm, elem, qFieldC("key"), keyX)
    }
    if name == "count" {
        let q = p + 2
        if toks.kindAt(q) == 100 { q = q + 1  if toks.kindAt(q) == 101 { q = q + 1 } }
        return QRes { code: qNodeC("QAgg", ".fn = xc_string_from_cstr(\"count\"), .operand = xc_box_QueryExpr(" + qLitC("xstd_json_number(0)") + ")"), pos: q, xtyp: "Integer" }
    }
    if name == "sum" or name == "avg" or name == "min" or name == "max" {
        let bo = p + 2
        if toks.kindAt(bo) != 102 {
            diag_error(tokenArrGet(toks, p + 1).line, "xi-query: ." + name + " expects a lambda over the group's rows, e.g. it." + name + " { x => x.amount }")
        }
        let close = toks.matchBrace(bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let iprm = "it"
        let bstart = bo + 1
        if arrow >= 0 { iprm = toks.textAt(bo + 1)  bstart = arrow + 1 }
        let body = qreifyExpr(toks, bstart, ctx, iprm, inner)
        return QRes { code: qNodeC("QAgg", ".fn = xc_string_from_cstr(\"" + name + "\"), .operand = xc_box_QueryExpr(" + body.code + ")"), pos: close + 1, xtyp: "Number" }
    }
    diag_error(tokenArrGet(toks, p + 1).line, "xi-query: unknown group member '" + name + "' — use it.key or an aggregate (count, sum, avg, min, max)")
    return QRes { code: "", pos: p + 2, xtyp: "" }
}

// Parse one braced lambda `{ [x =>] expr }` and reify it over `elem`.
mapper qreifyLambda(toks: Token[], bo: Integer, ctx: GCtx, elem: String) -> QRes {
    let close = toks.matchBrace(bo)
    let arrow = lambdaArrow(toks, bo + 1, close)
    let prm = "it"
    let bstart = bo + 1
    if arrow >= 0 { prm = toks.textAt(bo + 1)  bstart = arrow + 1 }
    let body = qreifyExpr(toks, bstart, ctx, prm, elem)
    return QRes { code: body.code, pos: close + 1, xtyp: body.xtyp }
}

// The element behind a Query_/QueryL_ xtype ("" if neither).
mapper qElemOf(typ: String) -> String {
    if typ.startsWith2("QueryL_") { return string_slice(typ, 7, string_len(typ)) }
    if typ.startsWith2("Query_") { return string_slice(typ, 6, string_len(typ)) }
    return ""
}

// ── stage + plan emitters ───────────────────────────────────────────
mapper qStageAppendC(recv: String, stage: String, u: String) -> String {
    return "({ xc_QueryPlan_t __qp" + u + " = " + recv + "; "
         + "xstd_list_push(__qp" + u + ".stages, (xc_QueryStage_t[]){ " + stage + " }); __qp" + u + "; })"
}

// `query.from<T>("source")` — seed a plan. pos is at the `query` identifier.
mapper genQueryFrom(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let line = tokenArrGet(toks, pos).line
    if not (ctx.prog).isSumTypeC("QueryStage") {
        diag_error(line, "query.from requires the query library — add:  import \"std/query.xi\"")
    }
    let p = pos + 3                                          // at '<'
    if toks.kindAt(p) != 114 {
        diag_error(line, "query.from expects a type argument:  query.from<T>(\"source\")")
    }
    let tname = toks.textAt(p + 1)
    if not (ctx.prog).isTypeNameC(tname) {
        diag_error(tokenArrGet(toks, p + 1).line, "unknown type '" + tname + "' — no type, event, or sum-type variant with that name is declared or imported")
    }
    p = p + 2
    if toks.kindAt(p) == 115 { p = p + 1 }                   // '>'
    // Source: a string literal, or any String expression (e.g. a repository's
    // `this.source` field). Default to the type name if `()` is empty.
    let srcC = "xc_string_from_cstr(\"" + tname + "\")"
    if toks.kindAt(p) == 100 {
        p = p + 1
        if toks.kindAt(p) == 4 {
            srcC = "xc_string_from_cstr(\"" + toks.textAt(p) + "\")"
            p = p + 1
        } else { if toks.kindAt(p) != 101 {
            let se = genExpr(toks, p, ctx)
            srcC = se.code
            p = se.pos
        } }
        if toks.kindAt(p) == 101 { p = p + 1 }
    }
    let code = "(xc_QueryPlan_t){ .source = " + srcC + ", .stages = xstd_list_new(sizeof(xc_QueryStage_t)), .rows = xstd_json_array() }"
    return ExprRes { code: code, pos: p, xtyp: "Query_" + tname, owned: false }
}

// `someList.asQuery()` / `someArr.asQuery()` — root a plan at an in-memory
// collection: the rows are snapshotted into the plan (source "$inline") and
// the chain runs locally with `.toList()`. `recvTyp` is the List/array xtype;
// p is at the '.' of `.asQuery`.
mapper genListAsQuery(toks: Token[], p: Integer, recv: String, recvTyp: String, ctx: GCtx) -> ExprRes {
    let line = tokenArrGet(toks, p + 1).line
    if not (ctx.prog).isSumTypeC("QueryStage") {
        diag_error(line, "asQuery requires the query library — add:  import \"std/query.xi\"")
    }
    let elem = ""
    if recvTyp.isListXType() { elem = recvTyp.listElemXName() } else {
        elem = string_slice(recvTyp, 4, string_len(recvTyp)).xnameFromArrSuffix()
    }
    let rowsC = jsonOfPayload(ctx.prog, recvTyp, recv)
    let q = p + 2
    if toks.kindAt(q) == 100 { q = q + 1  if toks.kindAt(q) == 101 { q = q + 1 } }   // ()
    let code = "(xc_QueryPlan_t){ .source = xc_string_from_cstr(\"$inline\"), .stages = xstd_list_new(sizeof(xc_QueryStage_t)), .rows = " + rowsC + " }"
    return ExprRes { code: code, pos: q, xtyp: "QueryL_" + elem, owned: false }
}

// One chained stage on a Query_<elem> / QueryL_<elem> receiver. p is at the
// '.'; the QueryL_ prefix marks a list-rooted (local) query.
mapper genQueryStage(toks: Token[], p: Integer, recv: String, typ: String, ctx: GCtx) -> ExprRes {
    let local = typ.startsWith2("QueryL_")
    let pfx = "Query_"
    if local { pfx = "QueryL_" }
    let elem = string_slice(typ, string_len(pfx), string_len(typ))
    let fld = toks.textAt(p + 1)
    let u = int_to_string(p)
    let line = tokenArrGet(toks, p + 1).line

    if fld == "filter" or fld == "map" or fld == "sortedBy" or fld == "sortedByDescending" {
        let bo = p + 2                                       // '{'
        if toks.kindAt(bo) != 102 {
            diag_error(line, "xi-query: ." + fld + " expects a lambda block, e.g. ." + fld + " { it... }")
        }
        let close = toks.matchBrace(bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let prm = "it"
        let bstart = bo + 1
        if arrow >= 0 { prm = toks.textAt(bo + 1)  bstart = arrow + 1 }
        let body = qreifyExpr(toks, bstart, ctx, prm, elem)
        let stage = ""
        let newTyp = typ
        if fld == "filter" {
            stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QFilter, .u.QFilter = { .pred = " + body.code + " } }"
        }
        if fld == "map" {
            stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QProject, .u.QProject = { .expr = " + body.code + " } }"
            if string_len(body.xtyp) > 0 { newTyp = pfx + body.xtyp }
        }
        if fld == "sortedBy" {
            stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QSortBy, .u.QSortBy = { .key = " + body.code + ", .desc = 0 } }"
        }
        if fld == "sortedByDescending" {
            stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QSortBy, .u.QSortBy = { .key = " + body.code + ", .desc = 1 } }"
        }
        return ExprRes { code: qStageAppendC(recv, stage, u), pos: close + 1, xtyp: newTyp, owned: false }
    }

    if fld == "take" or fld == "drop" {
        let ae = genExpr(toks, p + 3, ctx)
        let q = ae.pos
        if toks.kindAt(q) == 101 { q = q + 1 }
        let vtag = "QTake"
        if fld == "drop" { vtag = "QDrop" }
        let stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_" + vtag + ", .u." + vtag + " = { .n = (xc_integer_t)(" + ae.code + ") } }"
        return ExprRes { code: qStageAppendC(recv, stage, u), pos: q, xtyp: typ, owned: false }
    }

    if fld == "concat" {
        let ae = genExpr(toks, p + 3, ctx)
        let q = ae.pos
        if toks.kindAt(q) == 101 { q = q + 1 }
        if qElemOf(ae.xtyp) != elem {
            diag_error(line, "xi-query: .concat expects another query of the same element type (" + elem + ", got " + qElemOf(ae.xtyp) + ")")
        }
        let stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QConcat, .u.QConcat = { .right = " + ae.code + " } }"
        return ExprRes { code: qStageAppendC(recv, stage, u), pos: q, xtyp: typ, owned: false }
    }

    if fld == "groupBy" {
        let bo = p + 2
        if toks.kindAt(bo) != 102 {
            diag_error(line, "xi-query: .groupBy expects a lambda block, e.g. .groupBy { it.city }")
        }
        let key = qreifyLambda(toks, bo, ctx, elem)
        let kx = key.xtyp
        if string_len(kx) == 0 { kx = "String" }
        let stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QGroupBy, .u.QGroupBy = { .key = " + key.code + " } }"
        return ExprRes { code: qStageAppendC(recv, stage, u), pos: key.pos, xtyp: pfx + "qgroup:" + elem + ":" + kx, owned: false }
    }

    if fld == "join" {
        if elem.startsWith2("qpair:") or elem.startsWith2("qgroup:") {
            diag_error(line, "xi-query: .join on an already joined or grouped query isn't supported — project it with .map first")
        }
        let ae = genExpr(toks, p + 3, ctx)
        if not (ae.xtyp.startsWith2("Query_") or ae.xtyp.startsWith2("QueryL_")) {
            diag_error(line, "xi-query: .join expects another query as its first argument")
        }
        let relem = qElemOf(ae.xtyp)
        if relem.startsWith2("qpair:") or relem.startsWith2("qgroup:") {
            diag_error(line, "xi-query: .join on an already joined or grouped query isn't supported — project it with .map first")
        }
        let q = ae.pos
        if toks.kindAt(q) == 106 { q = q + 1 }               // ,
        if toks.kindAt(q) != 102 {
            diag_error(line, "xi-query: .join expects two key lambdas:  .join(other, { it.id }, { it.ownerId })")
        }
        let lk = qreifyLambda(toks, q, ctx, elem)
        q = lk.pos
        if toks.kindAt(q) == 106 { q = q + 1 }               // ,
        if toks.kindAt(q) != 102 {
            diag_error(line, "xi-query: .join expects two key lambdas:  .join(other, { it.id }, { it.ownerId })")
        }
        let rk = qreifyLambda(toks, q, ctx, relem)
        q = rk.pos
        if toks.kindAt(q) == 101 { q = q + 1 }               // )
        let stage = "(xc_QueryStage_t){ .tag = xc_QueryStage_QJoin, .u.QJoin = { .right = " + ae.code + ", .leftKey = " + lk.code + ", .rightKey = " + rk.code + " } }"
        return ExprRes { code: qStageAppendC(recv, stage, u), pos: q, xtyp: pfx + "qpair:" + elem + ":" + relem, owned: false }
    }

    if fld == "using" {
        // bind a provider to the query so the terminals run against it, no DI.
        // Store the fat-pointer halves as opaque handles (see QueryPlan).
        let ae = genExpr(toks, p + 3, ctx)
        let q = ae.pos
        if toks.kindAt(q) == 101 { q = q + 1 }
        let code = "({ xc_QueryPlan_t __qp" + u + " = " + recv + "; xc_QueryProvider_t __qpp" + u + " = " + ae.code + "; "
                 + "__qp" + u + ".providerSelf = __qpp" + u + ".self; __qp" + u + ".providerVtable = (void*)__qpp" + u + ".vtable; __qp" + u + "; })"
        return ExprRes { code: code, pos: q, xtyp: typ, owned: false }
    }

    if fld == "collect" or fld == "toList" or fld == "first" {
        // Terminals. `collect(p)` runs against the explicit provider `p`.
        // `collect()` / `toList()` / `first()` run against the query's bound
        // provider (set by `.using`); with none bound they fall back to the
        // module's DI-resolved provider (source-rooted) or an ephemeral
        // MemorySource (list-rooted). `first` yields the first row as `T?`.
        if elem.startsWith2("qpair:") or elem.startsWith2("qgroup:") {
            diag_error(line, "xi-query: project joined/grouped rows with .map { ... } before ." + fld)
        }
        let ct = elem.xnameToCtype()
        // an explicit provider arg (collect(p)) — otherwise use the bound/fallback
        let hasArg = false
        let argCode = ""
        let q = p + 2
        if toks.kindAt(q) == 100 {
            q = q + 1
            if toks.kindAt(q) != 101 {
                let ae = genExpr(toks, q, ctx)
                hasArg = true  argCode = ae.code  q = ae.pos
            }
            if toks.kindAt(q) == 101 { q = q + 1 }
        }
        let fallback = "xc_resolve_QueryProvider()"
        if local { fallback = "xc_MemorySource_as_QueryProvider(xc_new_MemorySource())" }
        let bound = "(xc_QueryProvider_t){ .self = __qp" + u + ".providerSelf, .vtable = (const xc_QueryProvider_vtable_t*)__qp" + u + ".providerVtable }"
        let pick = "(__qp" + u + ".providerVtable ? " + bound + " : (" + fallback + "))"
        if hasArg { pick = argCode }
        let head = "({ xc_QueryPlan_t __qp" + u + " = " + recv + "; "
                 + "xc_QueryProvider_t __qv" + u + " = " + pick + "; "
                 + "xc_Json_t __qr" + u + " = __qv" + u + ".vtable->run(__qv" + u + ".self, __qp" + u + "); "
        if fld == "first" {
            let dec0 = jsonDecodeExpr(ctx.prog, ct, "xstd_json_at(__qr" + u + ", 0)")
            if string_len(dec0) == 0 {
                diag_error(line, "xi-query: can't decode rows into element type '" + elem + "'")
            }
            let code = head + "xc_opt_" + elem + "_t __qo" + u + "; __qo" + u + ".has_value = 0; "
                     + "if (xstd_json_length(__qr" + u + ") > 0) { __qo" + u + ".has_value = 1; __qo" + u + ".value = " + dec0 + "; } __qo" + u + "; })"
            return ExprRes { code: code, pos: q, xtyp: "opt_" + elem, owned: false }
        }
        let dec = jsonDecodeExpr(ctx.prog, ct, "xstd_json_at(__qr" + u + ", __qi" + u + ")")
        if string_len(dec) == 0 {
            diag_error(line, "xi-query: can't decode rows into element type '" + elem + "'")
        }
        let code = head + "xc_List_t __ql" + u + " = xstd_list_new(sizeof(" + ct + ")); "
                 + "for (xc_integer_t __qi" + u + " = 0; __qi" + u + " < xstd_json_length(__qr" + u + "); __qi" + u + "++) { "
                 + ct + " __qe" + u + " = " + dec + "; "
                 + "xstd_list_push(__ql" + u + ", (" + ct + "[]){ __qe" + u + " }); } __ql" + u + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_" + elem, owned: false }
    }

    if fld == "plan" {
        // escape hatch: the reified plan value itself (e.g. to pass around or log)
        return ExprRes { code: recv, pos: p + 2, xtyp: "QueryPlan", owned: false }
    }

    diag_error(line, "xi-query: unknown stage '." + fld + "' — supported: filter, map, sortedBy, sortedByDescending, take, drop, concat, join, groupBy, using, collect, toList, first, plan")
    return ExprRes { code: recv, pos: p + 2, xtyp: typ, owned: false }
}