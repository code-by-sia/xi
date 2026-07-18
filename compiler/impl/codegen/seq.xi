// xc codegen — lazy sequences, eager list/collection ops, captures
// (part of the xc code generator — Program -> C99; spliced via codegen.xi)

// Lazy sequences: `list.asSequence().<lazy ops>.<terminal>` fuses the whole
// chain into ONE loop (no intermediate lists). `p` is at the `.` of asSequence;
// `src` is the source list code, `elemX0` its element xtype.
mapper genSequenceChain(toks: Token[], p: Integer, src: String, elemX0: String, ctx: GCtx, genMode: Bool, seedC: String, genBodyC: String, genParam: String) -> ExprRes {
    let u = int_to_string(p)
    let sv = "_sq" + u
    let iv = "_qi" + u
    let gv = "_gv" + u
    let q = p + 2
    if toks.kindAt(q) == 100 { q = q + 1  if toks.kindAt(q) == 101 { q = q + 1 } }   // ()
    let curVar = "_e" + u + "_0"
    let curX = elemX0
    let curC = curX.xnameToCtype()
    let genC = curC                                        // running-value (seed) type for generateSequence
    let pre = ""                                            // decls before the loop (counters)
    // list source: read the i-th element; generate source: read the running value
    // then advance it via the inlined generator (so a `continue` later is safe).
    let inner = "        " + curC + " " + curVar + " = *(" + curC + "*)xstd_list_at(" + sv + ", " + iv + ");\n"
    if genMode {
        inner = "        " + genC + " " + curVar + " = " + gv + ";\n"
              + "        { " + genC + " " + genParam + " = " + curVar + "; " + gv + " = (" + genBodyC + "); }\n"
    }
    let step = 0
    let going = true
    while going and toks.kindAt(q) == 107 {
        let fld = toks.textAt(q + 1)
        if fld == "map" or fld == "filter" or fld == "filterNot" or fld == "takeWhile" or fld == "dropWhile" {
            let bo = q + 2
            let close = toks.matchBrace(bo)
            let arrow = lambdaArrow(toks, bo + 1, close)
            let param = "it"
            let bstart = bo + 1
            if arrow >= 0 { param = toks.textAt(bo + 1)  bstart = arrow + 1 }
            let body = genExpr(toks, bstart, ctx.addSym(param, curX))
            // each op binds its param in its own block so reused names (e.g. `it`) don't clash
            if fld == "map" {
                step = step + 1
                let nv = "_e" + u + "_" + int_to_string(step)
                let nc = body.xtyp.xnameToCtype()
                inner = inner + "        " + nc + " " + nv + ";\n"
                inner = inner + "        { " + curC + " " + param + " = " + curVar + "; " + nv + " = (" + body.code + "); }\n"
                curVar = nv  curX = body.xtyp  curC = nc
            }
            if fld == "filter"    { inner = inner + "        { " + curC + " " + param + " = " + curVar + "; if (!(" + body.code + ")) continue; }\n" }
            if fld == "filterNot" { inner = inner + "        { " + curC + " " + param + " = " + curVar + "; if (("  + body.code + ")) continue; }\n" }
            if fld == "takeWhile" { inner = inner + "        { " + curC + " " + param + " = " + curVar + "; if (!(" + body.code + ")) break; }\n" }
            if fld == "dropWhile" {
                let dw = "_dw" + int_to_string(step) + u
                pre = pre + "xc_bool_t " + dw + " = 1; "
                inner = inner + "        { " + curC + " " + param + " = " + curVar + "; if (" + dw + " && (" + body.code + ")) continue; " + dw + " = 0; }\n"
                step = step + 1
            }
            q = close + 1
        } else {
        if fld == "take" or fld == "drop" {
            let ae = genExpr(toks, q + 3, ctx)
            let nstr = ae.code
            q = ae.pos
            if toks.kindAt(q) == 101 { q = q + 1 }
            let cv = "_c" + int_to_string(step) + u
            pre = pre + "xc_integer_t " + cv + " = 0; "
            if fld == "take" { inner = inner + "        if (" + cv + " >= (" + nstr + ")) break; " + cv + " = " + cv + " + 1;\n" }
            else { inner = inner + "        if (" + cv + " < (" + nstr + ")) { " + cv + " = " + cv + " + 1; continue; }\n" }
            step = step + 1
        } else {
            going = false                                   // a terminal
        } }
    }
    // terminal at q (`.fld(...)` or `.fld { ... }`)
    let head = "({ xc_List_t " + sv + " = " + src + "; " + pre + "\n"
    let loopHdr = "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
    if genMode {
        head = "({ " + genC + " " + gv + " = " + seedC + "; " + pre + "\n"   // seed the recurrence
        loopHdr = "      for (;;) {\n"                                       // infinite; a take/takeWhile/first bounds it
    }
    let tf = toks.textAt(q + 1)
    if tf == "toList" or tf == "toSet" {
        let add = "xstd_list_push"
        let tx = "List_" + curX.arrSuffixOf()
        let newc = "xstd_list_new(sizeof(" + curC + "))"
        if tf == "toSet" { add = "xstd_set_add"  tx = "Set_" + curX.arrSuffixOf()  newc = "xstd_set_new(sizeof(" + curC + "), " + curC.strFlagFor() + ")" }
        let code = head + "      __auto_type _out" + u + " = " + newc + ";\n" + loopHdr + inner
                 + "        " + add + "(_out" + u + ", &" + curVar + "); } _out" + u + "; })"
        return ExprRes { code: code, pos: q + 4, xtyp: tx , owned: false }
    }
    if tf == "forEach" {
        let bo = q + 2  let close = toks.matchBrace(bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let param = "it"  let bstart = bo + 1
        if arrow >= 0 { param = toks.textAt(bo + 1)  bstart = arrow + 1 }
        let body = genExpr(toks, bstart, ctx.addSym(param, curX))
        let code = head + loopHdr + inner + "        " + curC + " " + param + " = " + curVar + "; (void)(" + body.code + "); } (void)0; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "" , owned: false }
    }
    if tf == "fold" {
        let ae = genExpr(toks, q + 3, ctx)  let seed = ae.code  let accX = ae.xtyp
        let qq = ae.pos
        if toks.kindAt(qq) == 101 { qq = qq + 1 }
        let bo = qq  let close = toks.matchBrace(bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let pa = "acc"  let px = "x"  let bstart = bo + 1
        if arrow >= 0 {
            let pi = bo + 1  let firstP = true
            while pi < arrow { if toks.kindAt(pi) == 1 { if firstP { pa = toks.textAt(pi)  firstP = false } else { px = toks.textAt(pi) } } pi = pi + 1 }
            bstart = arrow + 1
        }
        let body = genExpr(toks, bstart, (ctx.addSym(pa, accX)).addSym(px, curX))
        let accC = accX.xnameToCtype()
        let code = head + "      " + accC + " " + pa + " = " + seed + ";\n" + loopHdr + inner
                 + "        " + curC + " " + px + " = " + curVar + "; " + pa + " = (" + body.code + "); } " + pa + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: accX , owned: false }
    }
    if tf == "count" {
        let code = head + "      xc_integer_t _c" + u + " = 0;\n" + loopHdr + inner + "        _c" + u + " = _c" + u + " + 1; } _c" + u + "; })"
        return ExprRes { code: code, pos: q + 4, xtyp: "Integer" , owned: false }
    }
    if tf == "sum" {
        let code = head + "      " + curC + " _s" + u + " = 0;\n" + loopHdr + inner + "        _s" + u + " = _s" + u + " + " + curVar + "; } _s" + u + "; })"
        return ExprRes { code: code, pos: q + 4, xtyp: curX , owned: false }
    }
    if tf == "any" or tf == "all" {
        let bo = q + 2  let close = toks.matchBrace(bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let param = "it"  let bstart = bo + 1
        if arrow >= 0 { param = toks.textAt(bo + 1)  bstart = arrow + 1 }
        let body = genExpr(toks, bstart, ctx.addSym(param, curX))
        let init = "0"  let setv = "1"  let cond = "(" + body.code + ")"
        if tf == "all" { init = "1"  setv = "0"  cond = "!(" + body.code + ")" }
        let code = head + "      xc_bool_t _r" + u + " = " + init + ";\n" + loopHdr + inner
                 + "        " + curC + " " + param + " = " + curVar + "; if (" + cond + ") { _r" + u + " = " + setv + "; break; } } _r" + u + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Bool" , owned: false }
    }
    if tf == "firstOrNone" {
        let suf = curX.arrSuffixOf()
        let code = head + "      xc_opt_" + suf + "_t _r" + u + "; _r" + u + ".has_value = 0;\n" + loopHdr + inner
                 + "        _r" + u + ".has_value = 1; _r" + u + ".value = " + curVar + "; break; } _r" + u + "; })"
        return ExprRes { code: code, pos: q + 4, xtyp: "opt_" + suf , owned: false }
    }
    // first() — first surviving element (aborts if none)
    let fcode = head + "      xc_opt_" + curX.arrSuffixOf() + "_t _r" + u + "; _r" + u + ".has_value = 0;\n" + loopHdr + inner
             + "        _r" + u + ".has_value = 1; _r" + u + ".value = " + curVar + "; break; }\n"
             + "      if (!_r" + u + ".has_value) { fprintf(stderr, \"xc: first() on an empty sequence\\n\"); abort(); } _r" + u + ".value; })"
    return ExprRes { code: fcode, pos: q + 4, xtyp: curX , owned: false }
}

// Build a stable insertion-sort over a copy of the list, keyed by `keyExpr`
// (computed once per element, `evar` bound to it). Numeric keys compare with
// `>`/`<`; String keys with xc_str_cmp. `desc` flips the order.
mapper sortStmtExpr(declSv: String, sv: String, rv: String, iv: String, u: String,
                    elem: String, evar: String, keyC: String, keyX: String, keyExpr: String, desc: Bool) -> String {
    let nN = "_n" + u
    let ks = "_ks" + u
    let ev = "_ev" + u
    let kv = "_kv" + u
    let jj = "_j" + u
    let cmp = ks + "[" + jj + "] > " + kv
    if keyX == "String" { cmp = "xc_str_cmp(" + ks + "[" + jj + "], " + kv + ") > 0" }
    if desc {
        cmp = ks + "[" + jj + "] < " + kv
        if keyX == "String" { cmp = "xc_str_cmp(" + ks + "[" + jj + "], " + kv + ") < 0" }
    }
    return "({ " + declSv
        + "xc_integer_t " + nN + " = xstd_list_len(" + sv + ");\n"
        + "      xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n"
        + "      " + keyC + "* " + ks + " = (" + keyC + "*)xc_obj_alloc((" + nN + " > 0 ? " + nN + " : 1) * sizeof(" + keyC + "));\n"
        + "      for (xc_integer_t " + iv + " = 0; " + iv + " < " + nN + "; " + iv + " = " + iv + " + 1) { "
        + elem + " " + evar + " = *(" + elem + "*)xstd_list_at(" + sv + ", " + iv + "); xstd_list_push(" + rv + ", &" + evar + "); " + ks + "[" + iv + "] = (" + keyExpr + "); }\n"
        + "      for (xc_integer_t " + iv + " = 1; " + iv + " < " + nN + "; " + iv + " = " + iv + " + 1) {\n"
        + "        " + elem + " " + ev + " = *(" + elem + "*)xstd_list_at(" + rv + ", " + iv + "); " + keyC + " " + kv + " = " + ks + "[" + iv + "]; xc_integer_t " + jj + " = " + iv + " - 1;\n"
        + "        while (" + jj + " >= 0 && (" + cmp + ")) { xstd_list_set(" + rv + ", " + jj + " + 1, xstd_list_at(" + rv + ", " + jj + ")); " + ks + "[" + jj + " + 1] = " + ks + "[" + jj + "]; " + jj + " = " + jj + " - 1; }\n"
        + "        xstd_list_set(" + rv + ", " + jj + " + 1, &" + ev + "); " + ks + "[" + jj + " + 1] = " + kv + "; }\n"
        + "      free(" + ks + "); " + rv + "; })"
}

// recv.<fld>([arg]) { [params =>] body } — emit an inlined loop (statement-expr).
mapper genListFunc(toks: Token[], p: Integer, recv: String, typ: String, fld: String, ctx: GCtx) -> ExprRes {
    let elem = typ.listElemCtype()
    let elemX = typ.listElemXName()
    let u = int_to_string(p)
    let sv = "_s" + u
    let iv = "_i" + u
    let rv = "_r" + u
    let suf = string_slice(typ, 5, string_len(typ))   // element arr-suffix (typ = "List_<suf>")
    let strF = elem.strFlagFor()
    let declSv = "xc_List_t " + sv + " = " + recv + ";\n      "
    let q = p + 2
    // optional leading (arg): take/drop count, fold seed, joinToString separator
    let argCode = ""
    let argX = ""
    if toks.kindAt(q) == 100 {
        if toks.kindAt(q + 1) == 101 {
            q = q + 2                                  // empty ()
        } else {
            let ae = genExpr(toks, q + 1, ctx)
            argCode = ae.code
            argX = ae.xtyp
            q = ae.pos
            if toks.kindAt(q) == 101 { q = q + 1 }
        }
    }

    // ── methods without a lambda (return here; pos = q) ──
    if fld == "reversed" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n"
                 + "      for (xc_integer_t " + iv + " = xstd_list_len(" + sv + ") - 1; " + iv + " >= 0; " + iv + " = " + iv + " - 1)\n"
                 + "        xstd_list_push(" + rv + ", xstd_list_at(" + sv + ", " + iv + ")); " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: typ , owned: false }
    }
    if fld == "take" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + ")); xc_integer_t _n" + u + " = (" + argCode + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + ") && " + iv + " < _n" + u + "; " + iv + " = " + iv + " + 1)\n"
                 + "        xstd_list_push(" + rv + ", xstd_list_at(" + sv + ", " + iv + ")); " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: typ , owned: false }
    }
    if fld == "drop" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n"
                 + "      for (xc_integer_t " + iv + " = (" + argCode + "); " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1)\n"
                 + "        xstd_list_push(" + rv + ", xstd_list_at(" + sv + ", " + iv + ")); " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: typ , owned: false }
    }
    if fld == "distinct" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + ")); xc_Set_t _seen" + u + " = xstd_set_new(sizeof(" + elem + "), " + strF + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        void* _e" + u + " = xstd_list_at(" + sv + ", " + iv + ");\n"
                 + "        if (!xstd_set_contains(_seen" + u + ", _e" + u + ")) { xstd_set_add(_seen" + u + ", _e" + u + "); xstd_list_push(" + rv + ", _e" + u + "); } } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: typ , owned: false }
    }
    if fld == "toSet" {
        let code = "({ " + declSv + "xc_Set_t " + rv + " = xstd_set_new(sizeof(" + elem + "), " + strF + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1)\n"
                 + "        xstd_set_add(" + rv + ", xstd_list_at(" + sv + ", " + iv + ")); " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "Set_" + suf , owned: false }
    }
    if fld == "first" {
        return ExprRes { code: "({ " + declSv + "*(" + elem + "*)xstd_list_at(" + sv + ", 0); })", pos: q, xtyp: elemX , owned: false }
    }
    if fld == "last" {
        return ExprRes { code: "({ " + declSv + "*(" + elem + "*)xstd_list_at(" + sv + ", xstd_list_len(" + sv + ") - 1); })", pos: q, xtyp: elemX , owned: false }
    }
    if fld == "firstOrNone" {
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0;\n"
                 + "      if (xstd_list_len(" + sv + ") > 0) { " + rv + ".has_value = 1; " + rv + ".value = *(" + elem + "*)xstd_list_at(" + sv + ", 0); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "opt_" + suf , owned: false }
    }
    if fld == "lastOrNone" {
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0;\n"
                 + "      if (xstd_list_len(" + sv + ") > 0) { " + rv + ".has_value = 1; " + rv + ".value = *(" + elem + "*)xstd_list_at(" + sv + ", xstd_list_len(" + sv + ") - 1); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "opt_" + suf , owned: false }
    }
    if fld == "sorted" or fld == "sortedDescending" {
        // natural order of primitive/String elements
        let evar = "_x" + u
        let code = sortStmtExpr(declSv, sv, rv, iv, u, elem, evar, elem, elemX, evar, fld == "sortedDescending")
        return ExprRes { code: code, pos: q, xtyp: typ , owned: false }
    }
    if fld == "chunked" {
        // split into consecutive sublists of size n -> List<List<T>>
        let jv = "_j" + u
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(xc_List_t)); xc_integer_t _n" + u + " = (" + argCode + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + _n" + u + ") {\n"
                 + "        xc_List_t _ch" + u + " = xstd_list_new(sizeof(" + elem + "));\n"
                 + "        for (xc_integer_t " + jv + " = " + iv + "; " + jv + " < " + iv + " + _n" + u + " && " + jv + " < xstd_list_len(" + sv + "); " + jv + " = " + jv + " + 1) xstd_list_push(_ch" + u + ", xstd_list_at(" + sv + ", " + jv + "));\n"
                 + "        xstd_list_push(" + rv + ", &_ch" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_List_" + suf , owned: false }
    }
    if fld == "windowed" {
        // sliding windows of size n, step 1 (only full windows) -> List<List<T>>
        let jv = "_j" + u
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(xc_List_t)); xc_integer_t _n" + u + " = (" + argCode + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " + _n" + u + " <= xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_List_t _ch" + u + " = xstd_list_new(sizeof(" + elem + "));\n"
                 + "        for (xc_integer_t " + jv + " = " + iv + "; " + jv + " < " + iv + " + _n" + u + "; " + jv + " = " + jv + " + 1) xstd_list_push(_ch" + u + ", xstd_list_at(" + sv + ", " + jv + "));\n"
                 + "        xstd_list_push(" + rv + ", &_ch" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_List_" + suf , owned: false }
    }

    if fld == "zip" {
        // zip(ys): List<A> x List<B> -> List<Pair<A,B>>, truncated to the shorter.
        let bX = argX.listElemXName()
        let bC = bX.xnameToCtype()
        let pX = elemX.pairXtype(bX)
        let ys = "_ys" + u
        let nn = "_n" + u
        let code = "({ " + declSv + "xc_List_t " + ys + " = (" + argCode + ");\n"
                 + "      xc_List_t " + rv + " = xstd_list_new(sizeof(xc_pair_t));\n"
                 + "      xc_integer_t " + nn + " = xstd_list_len(" + sv + "); xc_integer_t _m" + u + " = xstd_list_len(" + ys + "); if (_m" + u + " < " + nn + ") " + nn + " = _m" + u + ";\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < " + nn + "; " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_pair_t _pp" + u + " = xc_pair_make(xstd_list_at(" + sv + ", " + iv + "), sizeof(" + elem + "), xstd_list_at(" + ys + ", " + iv + "), sizeof(" + bC + "));\n"
                 + "        xstd_list_push(" + rv + ", &_pp" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_" + pX.arrSuffixOf() , owned: false }
    }
    if fld == "unzip" {
        // unzip: List<Pair<A,B>> -> Pair<List<A>, List<B>>.
        let aX = elemX.pairElem(0)
        let bX = elemX.pairElem(1)
        let aC = aX.xnameToCtype()
        let bC = bX.xnameToCtype()
        let la = "_la" + u
        let lb = "_lb" + u
        let code = "({ " + declSv + "xc_List_t " + la + " = xstd_list_new(sizeof(" + aC + ")); xc_List_t " + lb + " = xstd_list_new(sizeof(" + bC + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_pair_t* _pp" + u + " = (xc_pair_t*)xstd_list_at(" + sv + ", " + iv + "); xstd_list_push(" + la + ", _pp" + u + "->first); xstd_list_push(" + lb + ", _pp" + u + "->second); }\n"
                 + "      xc_pair_make(&" + la + ", sizeof(xc_List_t), &" + lb + ", sizeof(xc_List_t)); })"
        return ExprRes { code: code, pos: q, xtyp: ("List_" + aX.arrSuffixOf()).pairXtype("List_" + bX.arrSuffixOf()) , owned: true }
    }

    if fld == "sum" {
        // numeric total of the elements (0 for an empty list)
        let code = "({ " + declSv + elem + " " + rv + " = 0;\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1)\n"
                 + "        " + rv + " = " + rv + " + *(" + elem + "*)xstd_list_at(" + sv + ", " + iv + "); " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: elemX , owned: false }
    }
    if fld == "min" or fld == "max" {
        // natural min/max of primitive/String elements (aborts if empty)
        let bk = "_best" + u
        let cv = "_c" + u
        let cmp = cv + " < " + bk
        if fld == "max" { cmp = cv + " > " + bk }
        if elemX == "String" {
            cmp = "xc_str_cmp(" + cv + ", " + bk + ") < 0"
            if fld == "max" { cmp = "xc_str_cmp(" + cv + ", " + bk + ") > 0" }
        }
        let code = "({ " + declSv + "xc_integer_t _n" + u + " = xstd_list_len(" + sv + ");\n"
                 + "      if (_n" + u + " == 0) { fprintf(stderr, \"xc: " + fld + "() on an empty list\\n\"); abort(); }\n"
                 + "      " + elem + " " + bk + " = *(" + elem + "*)xstd_list_at(" + sv + ", 0);\n"
                 + "      for (xc_integer_t " + iv + " = 1; " + iv + " < _n" + u + "; " + iv + " = " + iv + " + 1) { " + elem + " " + cv + " = *(" + elem + "*)xstd_list_at(" + sv + ", " + iv + "); if (" + cmp + ") " + bk + " = " + cv + "; } " + bk + "; })"
        return ExprRes { code: code, pos: q, xtyp: elemX , owned: false }
    }
    if fld == "minOrNone" or fld == "maxOrNone" {
        // natural min/max as an optional (none if empty)
        let bk = "_best" + u
        let cv = "_c" + u
        let cmp = cv + " < " + bk
        if fld == "maxOrNone" { cmp = cv + " > " + bk }
        if elemX == "String" {
            cmp = "xc_str_cmp(" + cv + ", " + bk + ") < 0"
            if fld == "maxOrNone" { cmp = "xc_str_cmp(" + cv + ", " + bk + ") > 0" }
        }
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0; xc_integer_t _n" + u + " = xstd_list_len(" + sv + ");\n"
                 + "      if (_n" + u + " > 0) { " + elem + " " + bk + " = *(" + elem + "*)xstd_list_at(" + sv + ", 0);\n"
                 + "        for (xc_integer_t " + iv + " = 1; " + iv + " < _n" + u + "; " + iv + " = " + iv + " + 1) { " + elem + " " + cv + " = *(" + elem + "*)xstd_list_at(" + sv + ", " + iv + "); if (" + cmp + ") " + bk + " = " + cv + "; }\n"
                 + "        " + rv + ".has_value = 1; " + rv + ".value = " + bk + "; } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "opt_" + suf , owned: false }
    }
    if fld == "contains" or fld == "indexOf" {
        // membership / first index of a value (indexOf returns -1 if absent)
        let cv = "_c" + u
        let eq = cv + " == (" + argCode + ")"
        if elemX == "String" { eq = "xc_str_cmp(" + cv + ", (" + argCode + ")) == 0" }
        if fld == "contains" {
            let code = "({ " + declSv + "xc_bool_t " + rv + " = 0;\n"
                     + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) { " + elem + " " + cv + " = *(" + elem + "*)xstd_list_at(" + sv + ", " + iv + "); if (" + eq + ") { " + rv + " = 1; break; } } " + rv + "; })"
            return ExprRes { code: code, pos: q, xtyp: "Bool" , owned: false }
        }
        let code = "({ " + declSv + "xc_integer_t " + rv + " = -1;\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) { " + elem + " " + cv + " = *(" + elem + "*)xstd_list_at(" + sv + ", " + iv + "); if (" + eq + ") { " + rv + " = " + iv + "; break; } } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "Integer" , owned: false }
    }
    if fld == "toList" {
        // a shallow copy of the list
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1)\n"
                 + "        xstd_list_push(" + rv + ", xstd_list_at(" + sv + ", " + iv + ")); " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: typ , owned: false }
    }
    if fld == "withIndex" {
        // List<T> -> List<Pair<Integer, T>>
        let pX = "Integer".pairXtype(elemX)
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(xc_pair_t));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_integer_t _ix" + u + " = " + iv + ";\n"
                 + "        xc_pair_t _pp" + u + " = xc_pair_make(&_ix" + u + ", sizeof(xc_integer_t), xstd_list_at(" + sv + ", " + iv + "), sizeof(" + elem + "));\n"
                 + "        xstd_list_push(" + rv + ", &_pp" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_" + pX.arrSuffixOf() , owned: false }
    }
    if fld == "flatten" {
        // List<List<T>> -> List<T>
        let innerC = elemX.listElemCtype()
        let jv = "_j" + u
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + innerC + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_List_t _sub" + u + " = *(xc_List_t*)xstd_list_at(" + sv + ", " + iv + ");\n"
                 + "        for (xc_integer_t " + jv + " = 0; " + jv + " < xstd_list_len(_sub" + u + "); " + jv + " = " + jv + " + 1) xstd_list_push(" + rv + ", xstd_list_at(_sub" + u + ", " + jv + ")); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: elemX , owned: false }
    }

    // ── lambda methods:  { [params =>] body } ──
    let close = toks.matchBrace(q)
    let arrow = lambdaArrow(toks, q + 1, close)
    let p0 = "it"
    let p1 = ""
    let bstart = q + 1
    if arrow >= 0 {
        let pi = q + 1
        let firstP = true
        while pi < arrow {
            if toks.kindAt(pi) == 1 {
                if firstP { p0 = toks.textAt(pi)  firstP = false } else { p1 = toks.textAt(pi) }
            }
            pi = pi + 1
        }
        bstart = arrow + 1
    }
    let elAt = "*(" + elem + "*)xstd_list_at(" + sv + ", " + iv + ")"

    // two-param lambdas
    if fld == "fold" or fld == "reduce" {
        let accX = elemX
        if fld == "fold" { accX = argX }
        let bctx = (ctx.addSym(p0, accX)).addSym(p1, elemX)
        let body = genExpr(toks, bstart, bctx)
        let elDecl = "        " + elem + " " + p1 + " = " + elAt + ";\n"
        if fld == "fold" {
            let accC = accX.xnameToCtype()
            let loop = "({ " + declSv + accC + " " + p0 + " = " + argCode + ";\n"
                     + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                     + elDecl + "        " + p0 + " = (" + body.code + "); } " + p0 + "; })"
            return ExprRes { code: loop, pos: close + 1, xtyp: accX , owned: false }
        }
        let loop = "({ " + declSv + elem + " " + p0 + " = *(" + elem + "*)xstd_list_at(" + sv + ", 0);\n"
                 + "      for (xc_integer_t " + iv + " = 1; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + elDecl + "        " + p0 + " = (" + body.code + "); } " + p0 + "; })"
        return ExprRes { code: loop, pos: close + 1, xtyp: elemX , owned: false }
    }
    if fld == "scan" or fld == "runningFold" {
        // (init) { acc, x => body } — successive accumulations, including init.
        // Result is List<Acc> of length len+1.
        let accX = argX
        let accC = accX.xnameToCtype()
        let bctx = (ctx.addSym(p0, accX)).addSym(p1, elemX)
        let body = genExpr(toks, bstart, bctx)
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + accC + ")); " + accC + " " + p0 + " = " + argCode + ";\n"
                 + "      xstd_list_push(" + rv + ", &" + p0 + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        " + elem + " " + p1 + " = " + elAt + "; " + p0 + " = (" + body.code + "); xstd_list_push(" + rv + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "List_" + accX.arrSuffixOf() , owned: false }
    }
    if fld == "mapIndexed" {
        // { i, x => body } — p0 = index (Integer), p1 = element
        let bctx = (ctx.addSym(p0, "Integer")).addSym(p1, elemX)
        let body = genExpr(toks, bstart, bctx)
        let uc = body.xtyp.xnameToCtype()
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + uc + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_integer_t " + p0 + " = " + iv + "; " + elem + " " + p1 + " = " + elAt + ";\n"
                 + "        " + uc + " _v = (" + body.code + "); xstd_list_push(" + rv + ", &_v); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "List_" + body.xtyp.arrSuffixOf() , owned: false }
    }

    // single-param lambdas: p0 binds the element
    let bctx = ctx.addSym(p0, elemX)
    let body = genExpr(toks, bstart, bctx)
    let loopOpen = "for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        " + elem + " " + p0 + " = " + elAt + ";\n"

    if fld == "single" {
        // the one element matching the predicate (aborts if zero or many)
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0;\n      " + loopOpen
                 + "        if ((" + body.code + ")) { if (" + rv + ".has_value) { fprintf(stderr, \"xc: single() found more than one match\\n\"); abort(); } " + rv + ".has_value = 1; " + rv + ".value = " + p0 + "; } }\n"
                 + "      if (!" + rv + ".has_value) { fprintf(stderr, \"xc: single() found no match\\n\"); abort(); } " + rv + ".value; })"
        return ExprRes { code: code, pos: close + 1, xtyp: elemX , owned: false }
    }
    if fld == "singleOrNone" {
        // the one matching element as an optional (none if zero or many)
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0; xc_integer_t _cnt" + u + " = 0;\n      " + loopOpen
                 + "        if ((" + body.code + ")) { _cnt" + u + " = _cnt" + u + " + 1; " + rv + ".value = " + p0 + "; } }\n"
                 + "      " + rv + ".has_value = (_cnt" + u + " == 1); " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "opt_" + suf , owned: false }
    }
    if fld == "onEach" {
        // run a side effect per element, then return the list itself
        let code = "({ " + declSv + loopOpen + "        (void)(" + body.code + "); } " + sv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "maxOf" or fld == "minOf" {
        // the max/min projected value (aborts if empty)
        let keyC = body.xtyp.xnameToCtype()
        let bk = "_best" + u
        let kk = "_k" + u
        let cmp = kk + " < " + bk
        if fld == "maxOf" { cmp = kk + " > " + bk }
        if body.xtyp == "String" {
            cmp = "xc_str_cmp(" + kk + ", " + bk + ") < 0"
            if fld == "maxOf" { cmp = "xc_str_cmp(" + kk + ", " + bk + ") > 0" }
        }
        let code = "({ " + declSv + keyC + " " + bk + "; int _f" + u + " = 0;\n      " + loopOpen
                 + "        " + keyC + " " + kk + " = (" + body.code + "); if (!_f" + u + " || (" + cmp + ")) { " + bk + " = " + kk + "; _f" + u + " = 1; } }\n"
                 + "      if (!_f" + u + ") { fprintf(stderr, \"xc: " + fld + "() on an empty list\\n\"); abort(); } " + bk + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: body.xtyp , owned: false }
    }
    if fld == "map" {
        let uc = body.xtyp.xnameToCtype()
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + uc + "));\n      " + loopOpen
                 + "        " + uc + " _v = (" + body.code + "); xstd_list_push(" + rv + ", &_v); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "List_" + body.xtyp.arrSuffixOf() , owned: false }
    }
    if fld == "filter" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n      " + loopOpen
                 + "        if ((" + body.code + ")) xstd_list_push(" + rv + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "filterNot" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n      " + loopOpen
                 + "        if (!(" + body.code + ")) xstd_list_push(" + rv + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "partition" {
        // partition { pred }: List<T> -> Pair<List<T> matching, List<T> not>.
        let yes = "_yes" + u
        let no = "_no" + u
        let code = "({ " + declSv + "xc_List_t " + yes + " = xstd_list_new(sizeof(" + elem + ")); xc_List_t " + no + " = xstd_list_new(sizeof(" + elem + "));\n      " + loopOpen
                 + "        if ((" + body.code + ")) xstd_list_push(" + yes + ", &" + p0 + "); else xstd_list_push(" + no + ", &" + p0 + "); }\n"
                 + "      xc_pair_make(&" + yes + ", sizeof(xc_List_t), &" + no + ", sizeof(xc_List_t)); })"
        return ExprRes { code: code, pos: close + 1, xtyp: typ.pairXtype(typ) , owned: true }
    }
    if fld == "forEach" {
        let code = "({ " + declSv + loopOpen + "        (void)(" + body.code + "); } (void)0; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "" , owned: false }
    }
    if fld == "count" {
        let code = "({ " + declSv + "xc_integer_t " + rv + " = 0;\n      " + loopOpen
                 + "        if (" + body.code + ") " + rv + " = " + rv + " + 1; } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Integer" , owned: false }
    }
    if fld == "any" {
        let code = "({ " + declSv + "xc_bool_t " + rv + " = 0;\n      " + loopOpen
                 + "        if ((" + body.code + ")) { " + rv + " = 1; break; } } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Bool" , owned: false }
    }
    if fld == "all" {
        let code = "({ " + declSv + "xc_bool_t " + rv + " = 1;\n      " + loopOpen
                 + "        if (!(" + body.code + ")) { " + rv + " = 0; break; } } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Bool" , owned: false }
    }
    if fld == "none" {
        let code = "({ " + declSv + "xc_bool_t " + rv + " = 1;\n      " + loopOpen
                 + "        if ((" + body.code + ")) { " + rv + " = 0; break; } } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Bool" , owned: false }
    }
    if fld == "sumOf" {
        let sc = body.xtyp.xnameToCtype()
        let code = "({ " + declSv + sc + " " + rv + " = 0;\n      " + loopOpen
                 + "        " + rv + " = " + rv + " + (" + body.code + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: body.xtyp , owned: false }
    }
    if fld == "takeWhile" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + "));\n      " + loopOpen
                 + "        if (!(" + body.code + ")) break; xstd_list_push(" + rv + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "dropWhile" {
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + elem + ")); int _drop" + u + " = 1;\n      " + loopOpen
                 + "        if (_drop" + u + " && (" + body.code + ")) continue; _drop" + u + " = 0; xstd_list_push(" + rv + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "flatMap" {
        // body returns a List<U>; concatenate all sublists
        let uc = body.xtyp.listElemCtype()
        let jv = "_j" + u
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + uc + "));\n      " + loopOpen
                 + "        xc_List_t _sub" + u + " = (" + body.code + ");\n"
                 + "        for (xc_integer_t " + jv + " = 0; " + jv + " < xstd_list_len(_sub" + u + "); " + jv + " = " + jv + " + 1) xstd_list_push(" + rv + ", xstd_list_at(_sub" + u + ", " + jv + ")); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: body.xtyp , owned: false }
    }
    if fld == "find" {
        // first element matching the predicate, as an optional
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0;\n      " + loopOpen
                 + "        if ((" + body.code + ")) { " + rv + ".has_value = 1; " + rv + ".value = " + p0 + "; break; } } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "opt_" + suf , owned: false }
    }
    if fld == "maxByOrNone" or fld == "minByOrNone" {
        // element with the max/min numeric key, as an optional
        let keyC = body.xtyp.xnameToCtype()
        let cmp = " > "
        if fld == "minByOrNone" { cmp = " < " }
        let bk = "_best" + u
        let code = "({ " + declSv + "xc_opt_" + suf + "_t " + rv + "; " + rv + ".has_value = 0; " + keyC + " " + bk + " = 0;\n      " + loopOpen
                 + "        " + keyC + " _k" + u + " = (" + body.code + ");\n"
                 + "        if (!" + rv + ".has_value || _k" + u + cmp + bk + ") { " + rv + ".has_value = 1; " + rv + ".value = " + p0 + "; " + bk + " = _k" + u + "; } } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "opt_" + suf , owned: false }
    }
    if fld == "average" {
        // mean of a numeric projection (0.0 for an empty list)
        let code = "({ " + declSv + "xc_number_t _sum" + u + " = 0;\n      " + loopOpen
                 + "        _sum" + u + " = _sum" + u + " + (" + body.code + "); }"
                 + " xstd_list_len(" + sv + ") > 0 ? _sum" + u + " / (xc_number_t)xstd_list_len(" + sv + ") : 0.0; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Number" , owned: false }
    }
    if fld == "sortedBy" or fld == "sortedByDescending" {
        // sort by a numeric/String key projection
        let keyC = body.xtyp.xnameToCtype()
        let code = sortStmtExpr(declSv, sv, rv, iv, u, elem, p0, keyC, body.xtyp, body.code, fld == "sortedByDescending")
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "groupBy" {
        // Map<K, List<T>> — bucket elements by a key
        let kc = body.xtyp.xnameToCtype()
        let kstr = kc.strFlagFor()
        let code = "({ " + declSv + "xc_Map_t " + rv + " = xstd_map_new(sizeof(" + kc + "), sizeof(xc_List_t), " + kstr + ");\n      " + loopOpen
                 + "        " + kc + " _k" + u + " = (" + body.code + ");\n"
                 + "        if (!xstd_map_has(" + rv + ", &_k" + u + ")) { xc_List_t _nl" + u + " = xstd_list_new(sizeof(" + elem + ")); xstd_map_put(" + rv + ", &_k" + u + ", &_nl" + u + "); }\n"
                 + "        xc_List_t _lst" + u + " = *(xc_List_t*)xstd_map_get(" + rv + ", &_k" + u + "); xstd_list_push(_lst" + u + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Map_" + body.xtyp.arrSuffixOf() + "_List_" + suf , owned: false }
    }
    if fld == "associateBy" {
        // Map<K, T> — key each element by a projection (last wins)
        let kc = body.xtyp.xnameToCtype()
        let kstr = kc.strFlagFor()
        let code = "({ " + declSv + "xc_Map_t " + rv + " = xstd_map_new(sizeof(" + kc + "), sizeof(" + elem + "), " + kstr + ");\n      " + loopOpen
                 + "        " + kc + " _k" + u + " = (" + body.code + "); xstd_map_put(" + rv + ", &_k" + u + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Map_" + body.xtyp.arrSuffixOf() + "_" + suf , owned: false }
    }
    if fld == "associateWith" {
        // Map<T, V> — element is the key, value from a projection
        let vc = body.xtyp.xnameToCtype()
        let code = "({ " + declSv + "xc_Map_t " + rv + " = xstd_map_new(sizeof(" + elem + "), sizeof(" + vc + "), " + strF + ");\n      " + loopOpen
                 + "        " + vc + " _v" + u + " = (" + body.code + "); xstd_map_put(" + rv + ", &" + p0 + ", &_v" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Map_" + suf + "_" + body.xtyp.arrSuffixOf() , owned: false }
    }
    // joinToString(sep) { it => <string> }
    let sep = argCode
    if string_len(sep) == 0 { sep = "xc_string_from_cstr(\"\")" }
    let code = "({ " + declSv + "xc_string_t " + rv + " = xc_string_from_cstr(\"\");\n      " + loopOpen
             + "        if (" + iv + " > 0) " + rv + " = xc_string_concat(" + rv + ", " + sep + ");\n"
             + "        " + rv + " = xc_string_concat(" + rv + ", " + toStrC(body.code, body.xtyp) + "); } " + rv + "; })"
    return ExprRes { code: code, pos: close + 1, xtyp: "String" , owned: false }
}

// ── postfix:  .field  .method(args)  (call)  [index] ──────────────
// Declarations for `capture name: Type` bindings in a body: each captured name
// is declared (zero-initialized) at the function top, so the `(name = expr)`
// lowering can assign it and later statements can read it. Inert (empty) when a
// body uses no `capture`, so it never perturbs the self-host output.
mapper captureDecls(toks: Token[]) -> String {
    let out = ""
    let seen: String[] = []
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if toks.kindAt(i) == 1 and toks.textAt(i) == "capture"
           and toks.kindAt(i + 1) == 1 and toks.kindAt(i + 2) == 108 {
            let nm = toks.textAt(i + 1)
            let ty = toks.textAt(i + 3)               // type name (ident or primitive keyword)
            if not strArrContains(seen, nm) {
                seen = appendString(seen, nm)
                out = out + "    " + cTy(ty.xnameToCtype()) + " " + nm + " = {0};\n"
            }
        }
        i = i + 1
    }
    return out
}

// Seed `capture name: Type` bindings into the context so later references to the
// captured name resolve to its declared type.
mapper seedCaptures(ctx: GCtx, toks: Token[]) -> GCtx {
    let result = ctx
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if toks.kindAt(i) == 1 and toks.textAt(i) == "capture"
           and toks.kindAt(i + 1) == 1 and toks.kindAt(i + 2) == 108 {
            result = result.addSym(toks.textAt(i + 1), toks.textAt(i + 3))
        }
        i = i + 1
    }
    return result
}

