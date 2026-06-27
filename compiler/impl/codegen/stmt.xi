// xc codegen — statements: if/match/signal/try, hoists, parallel
// (part of the xc code generator — Program -> C99; spliced via codegen.xi)

// ── statements ────────────────────────────────────────────────────
mapper genStmts(toks: Token[], start: Integer, stop: Integer, ctx: GCtx) -> String {
    let out = ""
    let p = start
    let curCtx = ctx
    while p < stop and gkind(toks, p) != 0 {
        let sr = genStmt(toks, p, curCtx)
        out = out + sr.code
        curCtx = sr.ctx
        if sr.pos > p {
            p = sr.pos
        } else {
            p = p + 1
        }
    }
    return out
}

mapper genIf(toks: Token[], pos: Integer, ctx: GCtx) -> StmtRes {
    let p = pos + 1
    if gkind(toks, p) == 220 {
        let nm = gtext(toks, p + 1)
        let p2 = p + 2
        if gkind(toks, p2) == 111 { p2 = p2 + 1 }
        let e = genExpr(toks, p2, ctx)
        let pe = e.pos
        let close = matchBrace(toks, pe)
        // infer the unwrapped element's xtype from an "opt_<suffix>" optional
        let nmType = ""
        if startsWith2(e.xtyp, "opt_") { nmType = xnameFromArrSuffix(string_slice(e.xtyp, 4, string_len(e.xtyp))) }
        let bctx = ctx.addSym(nm, nmType)
        let body = "        __auto_type " + nm + " = (" + e.code + ").value;\n" + genStmts(toks, pe + 1, close, bctx)
        let code = "    if ((" + e.code + ").has_value) {\n" + body + "    }\n"
        return StmtRes { code: code, ctx: ctx, pos: close + 1 }
    }
    let c = genExpr(toks, p, ctx)
    let pc = c.pos
    let close = matchBrace(toks, pc)
    let body = genStmts(toks, pc + 1, close, ctx)
    let code = "    if (" + c.code + ") {\n" + body + "    }"
    let np = close + 1
    if gkind(toks, np) == 223 {
        if gkind(toks, np + 1) == 222 {
            let inner = genIf(toks, np + 1, ctx)
            code = code + " else " + inner.code
            np = inner.pos
        } else {
            let eclose = matchBrace(toks, np + 1)
            let ebody = genStmts(toks, np + 2, eclose, ctx)
            code = code + " else {\n" + ebody + "    }\n"
            np = eclose + 1
        }
    } else {
        code = code + "\n"
    }
    return StmtRes { code: code, ctx: ctx, pos: np }
}

// Value-showing assertion helpers usable in `test` bodies (and anywhere).
predicate isAssertHelper(name: String) {
    if name == "assertEq"    { return true }
    if name == "assertNe"    { return true }
    if name == "assertClose" { return true }
    if name == "assertOk"    { return true }
    if name == "assertErr"   { return true }
    return false
}
mapper genAssertHelper(toks: Token[], pos: Integer, ctx: GCtx) -> StmtRes {
    let name = gtext(toks, pos)
    let line = int_to_string(tokenArrGet(toks, pos).line)
    let loc = ", xc_src_file, " + line + "LL);\n"
    let a = genExpr(toks, pos + 2, ctx)        // pos+1 is '(', pos+2 first arg
    if name == "assertOk" or name == "assertErr" {
        let endp = a.pos
        if gkind(toks, endp) == 101 { endp = endp + 1 }
        let want = "1"
        if name == "assertErr" { want = "0" }
        let code = "    xc_assert_ok((" + a.code + ").ok, (" + a.code + ").err, " + want + loc
        return StmtRes { code: code, ctx: ctx, pos: endp }
    }
    // two-or-three operand forms: parse the rest
    let q = a.pos
    if gkind(toks, q) == 106 { q = q + 1 }     // ','
    let b = genExpr(toks, q, ctx)
    if name == "assertClose" {
        let r = b.pos
        if gkind(toks, r) == 106 { r = r + 1 }
        let eps = genExpr(toks, r, ctx)
        let endp = eps.pos
        if gkind(toks, endp) == 101 { endp = endp + 1 }
        let ok = "((((" + a.code + ") - (" + b.code + ")) <= (" + eps.code + ")) && (((" + b.code
               + ") - (" + a.code + ")) <= (" + eps.code + ")))"
        let code = "    xc_assert_close(" + ok + ", " + toStrC(a.code, "Number") + ", "
                 + toStrC(b.code, "Number") + ", " + toStrC(eps.code, "Number") + loc
        return StmtRes { code: code, ctx: ctx, pos: endp }
    }
    // assertEq / assertNe
    let endp = b.pos
    if gkind(toks, endp) == 101 { endp = endp + 1 }
    let eq = "((" + a.code + ") == (" + b.code + "))"
    if a.xtyp == "String" { eq = "(xc_str_cmp((" + a.code + "), (" + b.code + ")) == 0)" }
    let neg = "0"
    if name == "assertNe" { neg = "1" }
    let code = "    xc_assert_eq(" + eq + ", " + toStrC(a.code, a.xtyp) + ", " + toStrC(b.code, b.xtyp)
             + ", " + neg + loc
    return StmtRes { code: code, ctx: ctx, pos: endp }
}

mapper genStmt(toks: Token[], pos: Integer, ctx: GCtx) -> StmtRes {
    let k = gkind(toks, pos)
    if k == 220 {
        let name = gtext(toks, pos + 1)
        let p = pos + 2
        let declCtype = ""
        if gkind(toks, p) == 108 {
            declCtype = typeCtypeOf(toks, p + 1)
            while gkind(toks, p) != 111 and gkind(toks, p) != 0 { p = p + 1 }
        }
        if gkind(toks, p) == 111 { p = p + 1 }
        let e = genExpr(toks, p, ctx)
        let cdecl = "__auto_type"
        if string_len(declCtype) > 0 { cdecl = declCtype }
        // `let x = expr?` — Result error-propagation: bail out with the Err,
        // otherwise bind x to the unwrapped Ok value.
        if gkind(toks, e.pos) == 127 {
            let tmp = "_r" + int_to_string(pos)
            let line = "    __auto_type " + tmp + " = " + e.code + ";\n"
                     + "    if (!" + tmp + ".ok) return (" + ctx.retCtype + "){ .ok = false, .err = " + tmp + ".err };\n"
                     + "    " + cdecl + " " + name + " = " + tmp + ".value;\n"
            return StmtRes { code: line, ctx: ctx.addSym(name, ""), pos: e.pos + 1 }
        }
        let line = "    " + cdecl + " " + name + " = " + e.code + ";\n"
        return StmtRes { code: line, ctx: ctx.addSym(name, e.xtyp), pos: e.pos }
    }
    if k == 221 {
        let nk = gkind(toks, pos + 1)
        if nk == 0 or nk == 103 {
            return StmtRes { code: "    return;\n", ctx: ctx, pos: pos + 1 }
        }
        let e = genExpr(toks, pos + 1, ctx)
        let rc = e.code
        if rc == "{0}" {
            rc = "(" + ctx.retCtype + "){0}"
        }
        return StmtRes { code: "    return " + rc + ";\n", ctx: ctx, pos: e.pos }
    }
    if k == 222 {
        return genIf(toks, pos, ctx)
    }
    if k == 247 {
        let c = genExpr(toks, pos + 1, ctx)
        let close = matchBrace(toks, c.pos)
        let body = genStmts(toks, c.pos + 1, close, ctx)
        return StmtRes { code: "    while (" + c.code + ") {\n" + body + "    }\n", ctx: ctx, pos: close + 1 }
    }
    if k == 248 {
        let close = matchBrace(toks, pos + 1)
        let body = genStmts(toks, pos + 2, close, ctx)
        return StmtRes { code: "    for(;;) {\n" + body + "    }\n", ctx: ctx, pos: close + 1 }
    }
    // `scope { ... }` — run the body under a fresh arena, freed when it ends, so
    // a long-running (main-thread) loop reclaims each iteration. Don't `return`
    // out of a scope block (it would skip the arena restore); values that must
    // outlive the scope must be copied out.
    if k == 211 {
        let close = matchBrace(toks, pos + 1)
        let body = genStmts(toks, pos + 2, close, ctx)
        let code = "    { void* _sc = xc_scope_enter();\n" + body + "      xc_scope_leave(_sc); }\n"
        return StmtRes { code: code, ctx: ctx, pos: close + 1 }
    }
    if k == 249 { return StmtRes { code: "    break;\n", ctx: ctx, pos: pos + 1 } }
    if k == 250 { return StmtRes { code: "    continue;\n", ctx: ctx, pos: pos + 1 } }
    if k == 246 {
        let varName = gtext(toks, pos + 1)
        let p = pos + 2
        if gkind(toks, p) == 229 { p = p + 1 }
        let it = genExpr(toks, p, ctx)
        let close = matchBrace(toks, it.pos)
        let idv = "_i" + int_to_string(pos)
        let itv = "_it" + int_to_string(pos)
        if isListXType(it.xtyp) {
            // for x in <List<T>>
            let elem = listElemCtype(it.xtyp)
            let bctx = ctx.addSym(varName, listElemXName(it.xtyp))
            let body = genStmts(toks, it.pos + 1, close, bctx)
            let code = "    { xc_List_t " + itv + " = " + it.code + ";\n"
                     + "      for (xc_integer_t " + idv + " = 0; " + idv + " < xstd_list_len(" + itv + "); " + idv + " = " + idv + " + 1) {\n"
                     + "        " + elem + " " + varName + " = *(" + elem + "*)xstd_list_at(" + itv + ", " + idv + ");\n"
                     + body + "      } }\n"
            return StmtRes { code: code, ctx: ctx, pos: close + 1 }
        }
        if isSetXType(it.xtyp) {
            // for x in <Set<T>> — snapshot the live elements into a List, iterate it
            let elem = setElemCtype(it.xtyp)
            let bctx = ctx.addSym(varName, setElemXName(it.xtyp))
            let body = genStmts(toks, it.pos + 1, close, bctx)
            let code = "    { xc_List_t " + itv + " = xstd_set_items(" + it.code + ");\n"
                     + "      for (xc_integer_t " + idv + " = 0; " + idv + " < xstd_list_len(" + itv + "); " + idv + " = " + idv + " + 1) {\n"
                     + "        " + elem + " " + varName + " = *(" + elem + "*)xstd_list_at(" + itv + ", " + idv + ");\n"
                     + body + "      } }\n"
            return StmtRes { code: code, ctx: ctx, pos: close + 1 }
        }
        if it.xtyp == "Range" {
            // for i in <range> — a..b / until / downTo / step
            let bctx = ctx.addSym(varName, "Integer")
            let body = genStmts(toks, it.pos + 1, close, bctx)
            let code = "    { xc_range_t " + itv + " = " + it.code + ";\n"
                     + "      for (xc_integer_t " + varName + " = " + itv + ".start;\n"
                     + "           " + itv + ".step > 0 ? " + varName + " < " + itv + ".end : " + varName + " > " + itv + ".end;\n"
                     + "           " + varName + " = " + varName + " + " + itv + ".step) {\n"
                     + body + "      } }\n"
            return StmtRes { code: code, ctx: ctx, pos: close + 1 }
        }
        let bctx = ctx.addSym(varName, "")
        let body = genStmts(toks, it.pos + 1, close, bctx)
        let code = "    { __auto_type " + itv + " = " + it.code + ";\n"
                 + "      for (xc_size_t " + idv + " = 0; " + idv + " < " + itv + ".len; " + idv + " = " + idv + " + 1) {\n"
                 + "        __auto_type " + varName + " = " + itv + ".data[" + idv + "];\n"
                 + body + "      } }\n"
        return StmtRes { code: code, ctx: ctx, pos: close + 1 }
    }
    if k == 211 {
        let close = matchBrace(toks, pos + 2)
        let body = genStmts(toks, pos + 3, close, ctx)
        return StmtRes { code: "    {\n" + body + "    }\n", ctx: ctx, pos: close + 1 }
    }
    if k == 234 {
        let close = matchBrace(toks, pos + 1)
        let body = genStmts(toks, pos + 2, close, ctx)
        return StmtRes { code: "    {\n" + body + "    }\n", ctx: ctx, pos: close + 1 }
    }
    if k == 224 {
        return genMatch(toks, pos, ctx)
    }
    if k == 282 { return genSignal(toks, pos, ctx) }   // signal T {..} recover {..}
    if k == 283 { return genTry(toks, pos, ctx) }      // try {..} catch e: T {..}
    if k == 286 { return StmtRes { code: "    return 0;\n", ctx: ctx, pos: pos + 1 } }  // skip
    if k == 285 { return StmtRes { code: "    return 1;\n", ctx: ctx, pos: pos + 1 } }  // recover (resolution)
    // assert-family helpers (value-showing): assertEq/assertNe/assertClose/assertOk/assertErr
    if k == 1 and gkind(toks, pos + 1) == 100 and isAssertHelper(gtext(toks, pos)) {
        return genAssertHelper(toks, pos, ctx)
    }
    if k == 300 {   // assert <bool-expr> [ : "message" ]
        let e = genExpr(toks, pos + 1, ctx)
        let txt = ""
        let j = pos + 1
        while j < e.pos {
            if j > pos + 1 { txt = txt + " " }
            txt = txt + gtext(toks, j)
            j = j + 1
        }
        let line = int_to_string(tokenArrGet(toks, pos).line)
        let p = e.pos
        if gkind(toks, p) == 108 {                       // `:` — custom message
            let msg = gtext(toks, p + 1)
            let code = "    xc_assert_msg((" + e.code + "), \"" + cEscape(txt) + "\", \"" + cEscape(msg)
                     + "\", xc_src_file, " + line + "LL);\n"
            return StmtRes { code: code, ctx: ctx, pos: p + 2 }
        }
        let code = "    xc_assert((" + e.code + "), \"" + cEscape(txt) + "\", xc_src_file, "
                 + line + "LL);\n"
        return StmtRes { code: code, ctx: ctx, pos: e.pos }
    }
    let e = genExpr(toks, pos, ctx)
    let p = e.pos
    let ak = gkind(toks, p)
    if ak == 111 or ak == 130 or ak == 131 or ak == 132 or ak == 133 {
        let op = " = "
        if ak == 130 { op = " += " }
        if ak == 131 { op = " -= " }
        if ak == 132 { op = " *= " }
        if ak == 133 { op = " /= " }
        let rhs = genExpr(toks, p + 1, ctx)
        return StmtRes { code: "    " + e.code + op + rhs.code + ";\n", ctx: ctx, pos: rhs.pos }
    }
    // bare `expr?` statement — propagate Err, discard the Ok value
    if ak == 127 {
        let tmp = "_r" + int_to_string(pos)
        let line = "    __auto_type " + tmp + " = " + e.code + ";\n"
                 + "    if (!" + tmp + ".ok) return (" + ctx.retCtype + "){ .ok = false, .err = " + tmp + ".err };\n"
        return StmtRes { code: line, ctx: ctx, pos: p + 1 }
    }
    return StmtRes { code: "    " + e.code + ";\n", ctx: ctx, pos: p }
}

// match <expr> { pattern -> body, ... } lowered to an if/else chain.
// Patterns: literals (int/float/string/bool), `_` wildcard, or an identifier
// (binds the subject as a catch-all).
mapper genMatch(toks: Token[], pos: Integer, ctx: GCtx) -> StmtRes {
    let e = genExpr(toks, pos + 1, ctx)
    let p = e.pos
    let subj = "_m" + int_to_string(pos)
    let out = "    __auto_type " + subj + " = " + e.code + ";\n"
    if gkind(toks, p) == 102 { p = p + 1 }   // {
    let first = true
    let cont = true
    while cont and gkind(toks, p) != 103 and gkind(toks, p) != 0 {
        let pt = tokenArrGet(toks, p)
        let isWild = false
        let cond = ""
        let bindName = ""
        let bindExpr = subj
        if pt.kind == 223 {
            // `else -> ...` default arm (alias for `_`)
            isWild = true
            p = p + 1
        } else {
        if pt.kind == 100 {
            // multi-key selector: (lit, lit, ...) -> matches any listed literal
            p = p + 1
            let parts = ""
            while gkind(toks, p) != 101 and gkind(toks, p) != 0 {
                let lt = tokenArrGet(toks, p)
                let c1 = ""
                if lt.kind == 2 { c1 = subj + " == " + lt.text + "LL" } else {
                if lt.kind == 3 { c1 = subj + " == " + lt.text } else {
                if lt.kind == 4 { c1 = "xc_string_eq(" + subj + ", xc_string_from_cstr(\"" + lt.text + "\"))" } else {
                    c1 = "" } } }
                if string_len(c1) > 0 {
                    if string_len(parts) > 0 { parts = parts + " || " }
                    parts = parts + c1
                }
                p = p + 1
                if gkind(toks, p) == 106 { p = p + 1 }   // ,
            }
            if gkind(toks, p) == 101 { p = p + 1 }       // )
            cond = "(" + parts + ")"
        } else {
        if pt.kind == 1 and (ctx.prog).isVariantNameC(pt.text) {
            // sum-type variant pattern:  Variant [binding] -> body
            let sumN = (ctx.prog).sumOfVariant(pt.text)
            cond = subj + ".tag == xc_" + sumN + "_" + pt.text
            bindExpr = subj + ".u." + pt.text
            p = p + 1
            if gkind(toks, p) == 1 and gtext(toks, p) != "_" {
                bindName = gtext(toks, p)
                p = p + 1
            }
        } else {
        if pt.kind == 2 {
            cond = subj + " == " + pt.text + "LL"
            p = p + 1
        } else {
        if pt.kind == 3 {
            cond = subj + " == " + pt.text
            p = p + 1
        } else {
        if pt.kind == 4 {
            cond = "xc_string_eq(" + subj + ", xc_string_from_cstr(\"" + pt.text + "\"))"
            p = p + 1
        } else {
        if pt.kind == 236 {
            cond = subj
            p = p + 1
        } else {
        if pt.kind == 237 {
            cond = "(!" + subj + ")"
            p = p + 1
        } else {
            isWild = true
            if pt.kind == 1 {
                if pt.text == "_" { bindName = "" } else { bindName = pt.text }
            }
            p = p + 1
        } } } } } } } }
        if gkind(toks, p) == 109 { p = p + 1 }   // ->
        let bctx = ctx
        if string_len(bindName) > 0 { bctx = ctx.addSym(bindName, "") }
        let bindLine = ""
        if string_len(bindName) > 0 {
            bindLine = "        __auto_type " + bindName + " = " + bindExpr + ";\n"
        }
        let bodyCode = ""
        if gkind(toks, p) == 102 {
            let close = matchBrace(toks, p)
            bodyCode = genStmts(toks, p + 1, close, bctx)
            p = close + 1
        } else {
            // inline arm: `pattern -> expr` (single line) is sugar for `{ return expr }`.
            // Bound the expression to its own line so it can't swallow the next arm
            // (e.g. a following `(a, b) -> ...` would otherwise parse as a call).
            let ln0 = tokenArrGet(toks, p).line
            let q = p
            while gkind(toks, q) != 0 and gkind(toks, q) != 103 and tokenArrGet(toks, q).line == ln0 {
                q = q + 1
            }
            let sub: Token[] = []
            let si = p
            while si < q { sub = appendToken(sub, tokenArrGet(toks, si))  si = si + 1 }
            sub = appendToken(sub, Token { kind: 0, text: "", line: ln0 })
            let be = genExpr(sub, 0, bctx)
            let rc = be.code
            if rc == "{0}" { rc = "(" + ctx.retCtype + "){0}" }
            bodyCode = "        return " + rc + ";\n"
            p = q
        }
        if gkind(toks, p) == 106 { p = p + 1 }   // ,
        if isWild {
            if first {
                out = out + "    {\n" + bindLine + bodyCode + "    }\n"
            } else {
                out = out + "    else {\n" + bindLine + bodyCode + "    }\n"
            }
            cont = false
        } else {
            if first {
                out = out + "    if (" + cond + ") {\n" + bindLine + bodyCode + "    }\n"
            } else {
                out = out + "    else if (" + cond + ") {\n" + bindLine + bodyCode + "    }\n"
            }
        }
        first = false
    }
    if gkind(toks, p) == 103 { p = p + 1 }   // }
    return StmtRes { code: out, ctx: ctx, pos: p }
}

// signal T { fields } recover { block }
// Find the nearest handler for T (still on the stack), call it to get a
// resolution; recover -> run the inline block and continue; skip -> longjmp.
mapper genSignal(toks: Token[], pos: Integer, ctx: GCtx) -> StmtRes {
    let typeName = gtext(toks, pos + 1)
    let e = genExpr(toks, pos + 1, ctx)         // parses `T { ... }` (type literal)
    let recOpen = e.pos + 1                      // after `recover`
    let recClose = matchBrace(toks, recOpen)
    let recBody = genStmts(toks, recOpen + 1, recClose, ctx)
    let pl = "__pl" + int_to_string(pos)
    let hh = "__hh" + int_to_string(pos)
    let rr = "__res" + int_to_string(pos)
    let code = "    {\n"
             + "      xc_" + typeName + "_t " + pl + " = " + e.code + ";\n"
             + "      xc_handler_t* " + hh + " = xc_int_find(XC_INT_" + typeName + ");\n"
             + "      if (" + hh + " == ((void*)0)) xc_int_unhandled(\"" + typeName + "\");\n"
             + "      int " + rr + " = " + hh + "->fn(&" + pl + ");\n"
             + "      if (" + rr + ") {\n"
             + recBody
             + "      } else { longjmp(" + hh + "->unwind, 1); }\n"
             + "    }\n"
    return StmtRes { code: code, ctx: ctx, pos: recClose + 1 }
}

// try { body } catch e: T { ... }  — push a handler, setjmp the skip target,
// run the body; the catch body is compiled separately (see hoistCatches).
mapper genTry(toks: Token[], pos: Integer, ctx: GCtx) -> StmtRes {
    let bodyOpen = pos + 1
    let bodyClose = matchBrace(toks, bodyOpen)
    let body = genStmts(toks, bodyOpen + 1, bodyClose, ctx)
    let cp = bodyClose + 1                       // `catch`
    let typeName = gtext(toks, cp + 3)           // catch e : T
    let catchOpen = cp + 4
    let catchClose = matchBrace(toks, catchOpen)
    let hname = "xc_catch_" + ctx.fnTag + "_" + int_to_string(cp)
    let hv = "__h" + int_to_string(pos)
    let code = "    {\n"
             + "      xc_handler_t " + hv + ";\n"
             + "      " + hv + ".type_id = XC_INT_" + typeName + ";\n"
             + "      " + hv + ".fn = " + hname + ";\n"
             + "      " + hv + ".prev = xc_handlers; xc_handlers = &" + hv + ";\n"
             + "      if (setjmp(" + hv + ".unwind) == 0) {\n"
             + body
             + "      }\n"
             + "      xc_handlers = " + hv + ".prev;\n"
             + "    }\n"
    return StmtRes { code: code, ctx: ctx, pos: catchClose + 1 }
}

// Emit a `static int xc_catch_<tag>_<pos>(void* __pp)` for every `try`/`catch`
// in `toks`. The body reads only the payload (bound to the catch var) + globals;
// `skip`/`recover` lower to `return 0` / `return 1`.
mapper hoistCatches(prog: Program, toks: Token[], tag: String) -> String {
    let out = ""
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if gkind(toks, i) == 283 {              // try
            let bodyClose = matchBrace(toks, i + 1)
            let cp = bodyClose + 1               // catch
            if gkind(toks, cp) == 284 {
                let varName = gtext(toks, cp + 1)
                let typeName = gtext(toks, cp + 3)
                let catchOpen = cp + 4
                let catchClose = matchBrace(toks, catchOpen)
                let bctx = ((mkGCtx(prog)).addSym(varName, typeName)).withTag(tag)
                let cbody = genStmts(toks, catchOpen + 1, catchClose, bctx)
                let hname = "xc_catch_" + tag + "_" + int_to_string(cp)
                out = out + "static int " + hname + "(void* __pp) {\n"
                    + "    xc_" + typeName + "_t " + varName + " = *(xc_" + typeName + "_t*)__pp;\n"
                    + "    (void)" + varName + ";\n"
                    + cbody
                    + "    return 0;\n"
                    + "}\n"
            }
        }
        i = i + 1
    }
    return out
}

// ── `parallel { }` blocks (std/thread) ────────────────────────────
// A `parallel [(cap, ...)] { body }` expression spawns an OS thread running the
// body and yields a Thread handle. Captures must be channels (the only thing
// allowed to cross the share-nothing boundary); they are passed by value.
type ParallelParse = { caps: String[], bodyStart: Integer, bodyEnd: Integer, endPos: Integer }

// Parse the construct starting at `pos` (the `parallel` token).
mapper parseParallelAt(toks: Token[], pos: Integer) -> ParallelParse {
    let caps: String[] = []
    let p = pos + 1                       // past `parallel`
    if gkind(toks, p) == 100 {            // optional ( cap, ... )
        p = p + 1
        while gkind(toks, p) != 101 and gkind(toks, p) != 0 {
            if gkind(toks, p) == 1 { caps = appendString(caps, gtext(toks, p)) }
            p = p + 1
        }
        if gkind(toks, p) == 101 { p = p + 1 }   // )
    }
    // p is now at the body `{`
    let close = matchBrace(toks, p)
    return ParallelParse { caps: caps, bodyStart: p + 1, bodyEnd: close, endPos: close + 1 }
}

// Does `pos` start a `parallel` construct (ident "parallel" followed by ( or {)?
predicate isParallelAt(toks: Token[], pos: Integer) {
    if gkind(toks, pos) != 1 { return false }
    if gtext(toks, pos) != "parallel" { return false }
    let nk = gkind(toks, pos + 1)
    return nk == 100 or nk == 102
}

// Lift every `parallel` block in a function body to a top-level thread function
// plus a spawn helper, keyed by the block's token position (so genPrimary, which
// walks the same tokens, can name the same helper).
mapper hoistParallel(prog: Program, toks: Token[], tag: String) -> String {
    let out = ""
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if isParallelAt(toks, i) {
            let pp = parseParallelAt(toks, i)
            let id = tag + "_" + int_to_string(i)
            let nc = stringArrLen(pp.caps)
            if nc > 0 {
                out = out + "typedef struct {"
                let c = 0
                while c < nc { out = out + " xc_Channel_t " + stringArrGet(pp.caps, c) + ";"  c = c + 1 }
                out = out + " } xc_parenv_" + id + "_t;\n"
            }
            // thread body
            out = out + "static void* xc_par_" + id + "(void* __a) {\n"
            let bctx = ((mkGCtx(prog)).withRet("void")).withTag(id)
            if nc > 0 {
                out = out + "    xc_parenv_" + id + "_t* __e = (xc_parenv_" + id + "_t*)__a;\n"
                let c = 0
                while c < nc {
                    let nm = stringArrGet(pp.caps, c)
                    out = out + "    xc_Channel_t " + nm + " = __e->" + nm + ";\n"
                    bctx = bctx.addSym(nm, "Channel")
                    c = c + 1
                }
            } else {
                out = out + "    (void)__a;\n"
            }
            out = out + genStmts(toks, pp.bodyStart, pp.bodyEnd, bctx)
            out = out + "    return (void*)0;\n}\n"
            // spawn helper
            out = out + "static xc_Thread_t xc_parspawn_" + id + "("
            if nc > 0 {
                let c = 0
                while c < nc {
                    if c > 0 { out = out + ", " }
                    out = out + "xc_Channel_t " + stringArrGet(pp.caps, c)
                    c = c + 1
                }
            } else {
                out = out + "void"
            }
            out = out + ") {\n"
            if nc > 0 {
                out = out + "    xc_parenv_" + id + "_t* __e = (xc_parenv_" + id + "_t*)malloc(sizeof(*__e));\n"
                out = out + "    if (!__e) abort();\n"
                let c = 0
                while c < nc {
                    let nm = stringArrGet(pp.caps, c)
                    out = out + "    __e->" + nm + " = " + nm + ";\n"
                    c = c + 1
                }
                out = out + "    return xstd_thread_spawn(xc_par_" + id + ", (void*)__e);\n"
            } else {
                out = out + "    return xstd_thread_spawn(xc_par_" + id + ", (void*)0);\n"
            }
            out = out + "}\n"
        }
        i = i + 1
    }
    return out
}

// ── Code generator ────────────────────────────────────────────────

mapper mangle(name: String) -> String => name   // in X, names are already valid C identifiers (no dots in this context)

mapper indent(s: String) -> String => "    " + s

