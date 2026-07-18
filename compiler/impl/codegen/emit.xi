// xc codegen — function/method emission + DI (ctors, resolvers, factories)
// (part of the xc code generator — Program -> C99; spliced via codegen.xi)

// Generate the body of a function/method by converting body tokens to C
mapper genBody2(toks: Token[], ctx: GCtx) -> String => genStmts(toks, 0, tokenArrLen(toks), ctx)

predicate strArrContains(arr: String[], s: String) {
    let i = 0
    let n = stringArrLen(arr)
    while i < n {
        if stringArrGet(arr, i) == s { return true }
        i = i + 1
    }
    return false
}

mapper countFuncs(prog: Program, name: String) -> Integer {
    let i = 0
    let n = funcSpecLen(prog.functions)
    let c = 0
    while i < n {
        if funcSpecGet(prog.functions, i).name == name { c = c + 1 }
        i = i + 1
    }
    return c
}

// "xc_T_t a, xc_U_t b" -> "a, b"   (argument list for forwarding a call)
// A single ctype for C emission: a function type Fn(...) becomes the uniform
// closure value type xc_fn_t (its signature lives in the xtype, recovered at the
// call site). Other ctypes pass through.
mapper cTy(ct: String) -> String {
    if ct.isFnXType() { return "xc_fn_t" }
    return ct
}
// Translate one "ctype name" param segment for C emission (Fn(...) -> xc_fn_t).
mapper cSigSeg(seg: String) -> String {
    let n = string_len(seg)
    let s = 0
    while s < n and string_char_at(seg, s) == 32 { s = s + 1 }
    let lastSp = 0 - 1
    let j = s
    while j < n { if string_char_at(seg, j) == 32 { lastSp = j }  j = j + 1 }
    if lastSp < 0 { return seg }
    let ctype = string_slice(seg, s, lastSp)
    if ctype.isFnXType() { return string_slice(seg, 0, s) + "xc_fn_t" + string_slice(seg, lastSp, n) }
    return seg
}
// Translate a whole C param list for emission (each Fn(...) param -> xc_fn_t).
// v1 function types are single-argument, so no commas appear inside Fn(...).
mapper cSig(params: String) -> String {
    let out = ""
    let n = string_len(params)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(params, i) == 44 { isComma = true } }
        if atEnd or isComma {
            out = out + cSigSeg(string_slice(params, start, i))
            if isComma { out = out + "," }
            start = i + 1
        }
        i = i + 1
    }
    return out
}

mapper paramArgList(cparams: String) -> String {
    let n = string_len(cparams)
    if n == 0 { return "" }
    let out = ""
    let start = 0
    let i = 0
    let first = true
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(cparams, i) }
        if atEnd or c == 44 {
            let seg = string_slice(cparams, start, i)
            if not first { out = out + ", " }
            out = out + lastWord(seg)
            first = false
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return out
}

// Emit local declarations + auto-wiring for a function's dependency block.
mapper funcDepPrologue(prog: Program, dlist: DepSpec[]) -> String {
    let out = ""
    let i = 0
    let n = depSpecLen(dlist)
    while i < n {
        let dep = depSpecGet(dlist, i)
        out = out + "    " + dep.ctype + " " + dep.name + ";\n"
        out = out + wireDep(prog, dep, dep.name)
        i = i + 1
    }
    return out
}

// Add a function's deps to the context as locals (bare-name access).
mapper seedFuncDeps(ctx: GCtx, dlist: DepSpec[]) -> GCtx {
    let result = ctx
    let i = 0
    let n = depSpecLen(dlist)
    while i < n {
        let dep = depSpecGet(dlist, i)
        result = result.addSym(dep.name, dep.ifaceName)
        i = i + 1
    }
    return result
}

mapper emitOneFunc(prog: Program, fs: FuncSpec) -> String {
    let tag = fs.name
    let capN = fs.params.buildCapNames(fs.fnDeps)
    let capX = fs.params.buildCapXTypes(fs.fnDeps)
    let out = hoistCatches(prog, fs.bodyTokens, tag)
    out = out + hoistParallel(prog, fs.bodyTokens, tag)
    out = out + hoistLambdas(prog, fs.bodyTokens, tag)
    out = out + prog.hoistDelays(fs.bodyTokens, tag, capN, capX)
    // `async` free functions: the body returns the inner T (the Future wrapper is
    // applied at the call site via xc_spawn_<name>).
    let isAsync = fs.isAsync
    let retC = fs.retCtype
    if isAsync { retC = fs.asyncInnerCtype() }
    out = out + "static " + cTy(retC) + " xc_" + fs.name + "(" + cSig(fs.params) + ") {\n"
    out = out + funcDepPrologue(prog, fs.fnDeps)
    out = out + captureDecls(fs.bodyTokens)
    let ctx = seedCaptures(((seedFuncDeps((prog.newCtx().seedParams(fs.params)).withRet(retC), fs.fnDeps)).withTag(tag)).withCaps(capN, capX), fs.bodyTokens)
    out = out + genBody2(fs.bodyTokens, ctx)
    out = out + "}\n\n"
    if isAsync { out = out + fs.emitAsyncWrapper() }
    return out
}

// Emit a `where`-guarded overload set: each overload as xc_<name>__ovlK plus a
// dispatcher xc_<name> that picks the first overload whose guard holds.
mapper emitOverloadSet(prog: Program, name: String) -> String {
    let out = ""
    let dispatcher = ""
    let defaultCall = ""
    let haveDefault = false
    let firstParams = ""
    let firstRet = ""
    let argList = ""
    let firstSet = false
    let k = 0
    let idx = 0
    let n = funcSpecLen(prog.functions)
    while idx < n {
        let fs = funcSpecGet(prog.functions, idx)
        if fs.name == name {
            if not firstSet {
                firstParams = fs.params
                firstRet = fs.retCtype
                argList = paramArgList(fs.params)
                firstSet = true
            }
            let implName = name + "__ovl" + int_to_string(k)
            out = out + "static " + fs.retCtype + " xc_" + implName + "(" + fs.params + ") {\n"
            let bctx = (prog.newCtx().seedParams(fs.params)).withRet(fs.retCtype)
            out = out + genBody2(fs.bodyTokens, bctx)
            out = out + "}\n\n"
            let call = "xc_" + implName + "(" + argList + ")"
            if fs.hasWhere {
                let gctx = (prog.newCtx().seedParams(fs.params)).withRet(fs.retCtype)
                let g = genExpr(fs.whereTokens, 0, gctx)
                if firstRet == "void" {
                    dispatcher = dispatcher + "    if (" + g.code + ") { " + call + "; return; }\n"
                } else {
                    dispatcher = dispatcher + "    if (" + g.code + ") return " + call + ";\n"
                }
            } else {
                haveDefault = true
                if firstRet == "void" {
                    defaultCall = "    " + call + ";\n"
                } else {
                    defaultCall = "    return " + call + ";\n"
                }
            }
            k = k + 1
        }
        idx = idx + 1
    }
    out = out + "static " + firstRet + " xc_" + name + "(" + firstParams + ") {\n"
    out = out + dispatcher
    if haveDefault {
        out = out + defaultCall
    } else {
        out = out + "    XC_PANIC(\"no matching overload for " + name + "\");\n"
        if firstRet != "void" {
            out = out + "    return (" + firstRet + "){0};\n"
        }
    }
    out = out + "}\n\n"
    return out
}

// Is `name` a table-form `decision`? (Its body is emitted by genDecisionTables.)
predicate isTableDecision(prog: Program, name: String) {
    let i = 0
    let n = decisionTableLen(prog.tables)
    while i < n {
        if decisionTableGet(prog.tables, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper genFreeFunctions(prog: Program) -> String {
    let out = "/* === Free functions === */\n"
    let done: String[] = []
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let fs = funcSpecGet(prog.functions, i)
        if not strArrContains(done, fs.name) {
            done = appendString(done, fs.name)
            if isTableDecision(prog, fs.name) {
                // emitted directly by genDecisionTables
            } else {
                let cnt = countFuncs(prog, fs.name)
                if cnt == 1 and not fs.hasWhere {
                    out = out + emitOneFunc(prog, fs)
                } else {
                    out = out + emitOverloadSet(prog, fs.name)
                }
            }
        }
        i = i + 1
    }
    // scheduled jobs: each is a zero-arg, deps-wired function `xc_<name>()`
    let s = 0
    let sn = funcSpecLen(prog.scheduled)
    while s < sn {
        out = out + emitOneFunc(prog, funcSpecGet(prog.scheduled, s))
        s = s + 1
    }
    return out + "\n"
}

// One row's value as a C expression: the single output, or a `<Name>Out` record.
mapper decRowValue(prog: Program, t: DecisionTable, outs: Token[], ctx: GCtx) -> String {
    if not t.isMulti {
        return genExpr(outs, 0, ctx).code
    }
    let code = "(xc_" + t.name + "Out_t){ "
    let nseg = stringArrLen(t.outNames)
    let pos = 0
    let seg = 0
    while seg < nseg {
        let sub: Token[] = []
        let d = 0
        let go = true
        while go {
            let k = outs.kindAt(pos)
            if k == 0 { go = false }
            else {
                if d == 0 and k == 125 { go = false }
                else {
                    if k == 100 or k == 104 or k == 102 { d = d + 1 }
                    if k == 101 or k == 105 or k == 103 { d = d - 1 }
                    sub = appendToken(sub, tokenArrGet(outs, pos))
                    pos = pos + 1
                }
            }
        }
        if outs.kindAt(pos) == 125 { pos = pos + 1 }
        if seg > 0 { code = code + ", " }
        code = code + "." + stringArrGet(t.outNames, seg) + " = " + genExpr(sub, 0, ctx).code
        seg = seg + 1
    }
    return code + " }"
}

// Direct codegen for table-form decisions (first / unique / collect [+ agg]).
mapper genDecisionTables(prog: Program) -> String {
    let out = "/* === Decision tables === */\n"
    let ti = 0
    let tn = decisionTableLen(prog.tables)
    while ti < tn {
        let t = decisionTableGet(prog.tables, ti)
        let ctx = prog.newCtx().seedParams(t.params)
        out = out + "static " + t.retCtype + " xc_" + t.name + "(" + t.params + ") {\n"
        let nr = decisionRowLen(t.rows)
        if t.policy == "first" {
            let r = 0
            while r < nr {
                let row = decisionRowGet(t.rows, r)
                let cond = "1"
                if tokenArrLen(row.cond) > 0 { cond = genExpr(row.cond, 0, ctx).code }
                out = out + "    if (" + cond + ") return " + decRowValue(prog, t, row.outs, ctx) + ";\n"
                r = r + 1
            }
            out = out + "    XC_PANIC(\"decision '" + t.name + "': no matching rule\");\n"
            out = out + "    { " + t.retCtype + " __z; memset(&__z, 0, sizeof(__z)); return __z; }\n"
        } else {
        if t.policy == "unique" {
            out = out + "    " + t.retElem + " __r; memset(&__r, 0, sizeof(__r)); xc_integer_t __m = 0;\n"
            let r = 0
            while r < nr {
                let row = decisionRowGet(t.rows, r)
                let cond = "1"
                if tokenArrLen(row.cond) > 0 { cond = genExpr(row.cond, 0, ctx).code }
                out = out + "    if (" + cond + ") { __m++; __r = " + decRowValue(prog, t, row.outs, ctx) + "; }\n"
                r = r + 1
            }
            out = out + "    if (__m != 1) XC_PANIC(\"decision '" + t.name + "': expected exactly one matching rule\");\n"
            out = out + "    return __r;\n"
        } else {
            // collect (+ optional aggregator)
            if t.agg == "count" {
                out = out + "    xc_integer_t __c = 0;\n"
                let r = 0
                while r < nr {
                    let row = decisionRowGet(t.rows, r)
                    let cond = "1"
                    if tokenArrLen(row.cond) > 0 { cond = genExpr(row.cond, 0, ctx).code }
                    out = out + "    if (" + cond + ") __c++;\n"
                    r = r + 1
                }
                out = out + "    return __c;\n"
            } else {
            if t.agg == "sum" {
                out = out + "    " + t.retElem + " __s; memset(&__s, 0, sizeof(__s));\n"
                let r = 0
                while r < nr {
                    let row = decisionRowGet(t.rows, r)
                    let cond = "1"
                    if tokenArrLen(row.cond) > 0 { cond = genExpr(row.cond, 0, ctx).code }
                    out = out + "    if (" + cond + ") __s = __s + (" + decRowValue(prog, t, row.outs, ctx) + ");\n"
                    r = r + 1
                }
                out = out + "    return __s;\n"
            } else {
            if t.agg == "min" or t.agg == "max" {
                let op = "<"
                if t.agg == "max" { op = ">" }
                out = out + "    " + t.retElem + " __b; memset(&__b, 0, sizeof(__b)); int __seen = 0;\n"
                let r = 0
                while r < nr {
                    let row = decisionRowGet(t.rows, r)
                    let cond = "1"
                    if tokenArrLen(row.cond) > 0 { cond = genExpr(row.cond, 0, ctx).code }
                    let v = decRowValue(prog, t, row.outs, ctx)
                    out = out + "    if (" + cond + ") { " + t.retElem + " __v = " + v + "; if (!__seen || __v " + op + " __b) __b = __v; __seen = 1; }\n"
                    r = r + 1
                }
                out = out + "    return __b;\n"
            } else {
                // raw collect -> fixed-capacity list of element values
                out = out + "    long __M = " + int_to_string(nr) + ";\n"
                out = out + "    " + t.retElem + "* __buf = __M > 0 ? (" + t.retElem + "*)xc_obj_alloc((xc_size_t)__M * sizeof(" + t.retElem + ")) : (" + t.retElem + "*)0;\n"
                out = out + "    xc_size_t __n = 0;\n"
                let r = 0
                while r < nr {
                    let row = decisionRowGet(t.rows, r)
                    let cond = "1"
                    if tokenArrLen(row.cond) > 0 { cond = genExpr(row.cond, 0, ctx).code }
                    out = out + "    if (" + cond + ") { __buf[__n] = " + decRowValue(prog, t, row.outs, ctx) + "; __n++; }\n"
                    r = r + 1
                }
                out = out + "    { " + t.retCtype + " __res; __res.data = __buf; __res.len = __n; __res.cap = (xc_size_t)__M; return __res; }\n"
            }
            }
            }
        }
        }
        out = out + "}\n\n"
        ti = ti + 1
    }
    return out
}

// Seed a class's deps as dep-symbols (accessed via self->)
mapper seedDeps(ctx: GCtx, cs: ClassSpec) -> GCtx {
    let result = ctx
    let di = 0
    let dn = depSpecLen(cs.depList)
    while di < dn {
        let dep = depSpecGet(cs.depList, di)
        result = result.addDep(dep.name, dep.ifaceName)
        di = di + 1
    }
    return result
}

// How many non-creator methods of `cs` share this name (overload-set size).
mapper countMethodName(cs: ClassSpec, name: String) -> Integer {
    let c = 0
    let mi = 0
    let mn = methodSpecLen(cs.methList)
    while mi < mn {
        let ms = methodSpecGet(cs.methList, mi)
        if ms.kind != "creator" and ms.name == name { c = c + 1 }
        mi = mi + 1
    }
    return c
}

// 0-based ordinal of method `idx` among same-named non-creator methods.
mapper methodOrdinal(cs: ClassSpec, idx: Integer) -> Integer {
    let target = methodSpecGet(cs.methList, idx).name
    let c = 0
    let mi = 0
    while mi < idx {
        let ms = methodSpecGet(cs.methList, mi)
        if ms.kind != "creator" and ms.name == target { c = c + 1 }
        mi = mi + 1
    }
    return c
}

// Is method `idx` the last one carrying its name?
predicate isLastOfName(cs: ClassSpec, idx: Integer) {
    let target = methodSpecGet(cs.methList, idx).name
    let mi = idx + 1
    let mn = methodSpecLen(cs.methList)
    while mi < mn {
        let ms = methodSpecGet(cs.methList, mi)
        if ms.kind != "creator" and ms.name == target { return false }
        mi = mi + 1
    }
    return true
}

// Comma-separated parameter *names* from a C param string ("ctype a, ctype b" -> "a, b").
mapper paramNames(params: String) -> String {
    let out = ""
    let n = string_len(params)
    if n == 0 { return "" }
    let start = 0
    let i = 0
    let first = true
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(params, i) }
        if atEnd or c == 44 {
            let nm = lastWord(string_slice(params, start, i))
            if not first { out = out + ", " }
            out = out + nm
            first = false
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return out
}

// A `where`-overloaded method becomes N per-overload bodies plus a dispatcher
// (named like the un-overloaded impl, so vtables/casters need no change) that
// runs each guard in order and falls through to the un-guarded default.
mapper genMethodDispatcher(prog: Program, cs: ClassSpec, name: String, ret: String, params: String) -> String {
    let pstr = params
    if string_len(pstr) > 0 { pstr = ", " + pstr }
    let argfwd = "self_ptr"
    let names = paramNames(params)
    if string_len(names) > 0 { argfwd = argfwd + ", " + names }
    let out = "static " + ret + " xc_" + cs.name + "_" + name + "_impl(void* self_ptr" + pstr + ") {\n"
    out = out + "    xc_" + cs.name + "_t* self = (xc_" + cs.name + "_t*)self_ptr; (void)self;\n"
    let defaultOrd = 0 - 1
    let mi = 0
    let mn = methodSpecLen(cs.methList)
    while mi < mn {
        let ms = methodSpecGet(cs.methList, mi)
        if ms.kind != "creator" and ms.name == name {
            let k = methodOrdinal(cs, mi)
            if ms.hasWhere {
                let ctx = ((seedDeps(prog.newCtx(), cs).seedParams(params)).withRet(ret)).withTag(cs.name + "_" + name)
                let g = genExpr(ms.whereTokens, 0, ctx)
                out = out + "    if (" + g.code + ") { return xc_" + cs.name + "_" + name + "_ovl" + int_to_string(k) + "_impl(" + argfwd + "); }\n"
            } else {
                defaultOrd = k
            }
        }
        mi = mi + 1
    }
    if defaultOrd >= 0 {
        out = out + "    return xc_" + cs.name + "_" + name + "_ovl" + int_to_string(defaultOrd) + "_impl(" + argfwd + ");\n"
    } else {
        if ret == "void" {
            out = out + "    return;\n"
        } else {
            out = out + "    { " + ret + " _z; memset(&_z, 0, sizeof(_z)); return _z; }\n"
        }
    }
    return out + "}\n\n"
}

mapper genClassMethods(prog: Program) -> String {
    let out = "/* === Class method implementations === */\n"
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let ms = methodSpecGet(cs.methList, mi)
            let tag = cs.name + "_" + ms.name
            if ms.kind == "creator" {
                out = out + hoistCatches(prog, ms.bodyTokens, tag)
                out = out + hoistParallel(prog, ms.bodyTokens, tag)
                out = out + hoistLambdas(prog, ms.bodyTokens, tag)
                out = out + "static " + ms.retCtype + " xc_" + cs.name + "_" + ms.name + "(" + ms.params + ") {\n"
                out = out + funcDepPrologue(prog, ms.fnDeps)
                out = out + captureDecls(ms.bodyTokens)
                let ctx = seedCaptures(((seedFuncDeps(prog.newCtx().seedParams(ms.params), ms.fnDeps)).withRet(ms.retCtype)).withTag(tag), ms.bodyTokens)
                out = out + genBody2(ms.bodyTokens, ctx)
                out = out + "}\n\n"
            } else {
                let pstr = ms.params
                if string_len(pstr) > 0 { pstr = ", " + pstr }
                out = out + hoistCatches(prog, ms.bodyTokens, tag)
                out = out + hoistParallel(prog, ms.bodyTokens, tag)
                out = out + hoistLambdas(prog, ms.bodyTokens, tag)
                // Overloaded (multiple same-named, or `where`-guarded) methods emit
                // per-overload bodies + a dispatcher; otherwise a single _impl.
                let overloaded = countMethodName(cs, ms.name) > 1 or ms.hasWhere
                let implName = "xc_" + cs.name + "_" + ms.name + "_impl"
                if overloaded {
                    implName = "xc_" + cs.name + "_" + ms.name + "_ovl" + int_to_string(methodOrdinal(cs, mi)) + "_impl"
                }
                out = out + "static " + ms.retCtype + " " + implName + "(void* self_ptr" + pstr + ") {\n"
                out = out + "    xc_" + cs.name + "_t* self = (xc_" + cs.name + "_t*)self_ptr;\n"
                out = out + funcDepPrologue(prog, ms.fnDeps)
                out = out + captureDecls(ms.bodyTokens)
                let ctx = seedCaptures((((seedFuncDeps(seedDeps(prog.newCtx(), cs).seedParams(ms.params), ms.fnDeps)).withRet(ms.retCtype)).withTag(tag)).withSelfClass(cs.name), ms.bodyTokens)
                out = out + genBody2(ms.bodyTokens, ctx)
                out = out + "}\n\n"
                if overloaded and isLastOfName(cs, mi) {
                    out = out + genMethodDispatcher(prog, cs, ms.name, ms.retCtype, ms.params)
                }
            }
            mi = mi + 1
        }
        i = i + 1
    }
    return out + "\n"
}
