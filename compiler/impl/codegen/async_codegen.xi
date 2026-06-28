// xc codegen — async function wrappers + runWithDelay capture machinery.
//
// Single responsibility: lowering concurrency. An `async` free function gets a
// captured-args env struct + worker thunk + `xc_spawn_<name>` that returns a
// Future; a `runWithDelay { }` block is hoisted to a worker that sleeps then runs
// the captured body. Wrapper emission is an operation on the FuncSpec; the
// capture probes are operations on the token body; the hoist is driven from the
// Program (it needs the codegen context).

// A free function auto-spawns (its calls run on a worker and yield a Future)
// when marked `async`. A `-> Future<T>` return type is NOT auto-spawn: such a
// function returns a future value it built itself (e.g. from an async call or
// `runWithDelay`), which the caller can `await` directly.
predicate Program.isAsyncFuncC(name: String) {
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        let fs = funcSpecGet(this.functions, i)
        if fs.name == name { return fs.isAsync }
        i = i + 1
    }
    return false
}

// The value an async function's body actually returns (the inner T), as a C type.
mapper FuncSpec.asyncInnerCtype() -> String {
    if this.retCtype.isFutureCtype() { return this.retCtype.futureCtypeInner() }
    return this.retCtype
}

// "T a, U b" -> "T a; U b;" (struct fields for the captured-args env).
mapper String.cFields() -> String {
    let out = ""
    let n = string_len(this)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(this, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(this, start, i)
            if string_len(seg) > 0 { out = out + cSigSeg(seg) + "; " }
            start = i + 1
        }
        i = i + 1
    }
    return out
}
// "T a, U b" -> "__e->a = a; __e->b = b; " (copy args into the env struct).
mapper String.envAssigns() -> String {
    let out = ""
    let n = string_len(this)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(this, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(this, start, i)
            if string_len(seg) > 0 { let nm = lastWord(seg)  out = out + "__e->" + nm + " = " + nm + "; " }
            start = i + 1
        }
        i = i + 1
    }
    return out
}
// Like paramArgList but each name is prefixed (e.g. "__e->a, __e->b").
mapper String.paramArgListPrefixed(pfx: String) -> String {
    let n = string_len(this)
    if n == 0 { return "" }
    let out = ""
    let start = 0
    let i = 0
    let first = true
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(this, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(this, start, i)
            if string_len(seg) > 0 {
                if not first { out = out + ", " }
                out = out + pfx + lastWord(seg)
                first = false
            }
            start = i + 1
        }
        i = i + 1
    }
    return out
}

// For an async free function, emit the captured-args env struct, the worker
// thunk (runs the body, mallocs the T result), and `xc_spawn_<name>(params)`
// which packs the args and returns a Future. The call site calls xc_spawn_<name>.
mapper FuncSpec.emitAsyncWrapper() -> String {
    let inner = cTy(this.asyncInnerCtype())
    let nm = this.name
    let args = paramArgList(this.params)
    let hasArgs = string_len(this.params) > 0
    let out = ""
    if hasArgs { out = out + "typedef struct { " + this.params.cFields() + "} xc_aenv_" + nm + "_t;\n" }
    out = out + "static void* xc_athunk_" + nm + "(void* __p) {\n"
    if hasArgs {
        out = out + "    xc_aenv_" + nm + "_t* __e = (xc_aenv_" + nm + "_t*)__p;\n"
    } else {
        out = out + "    (void)__p;\n"
    }
    out = out + "    " + inner + "* __r = (" + inner + "*)malloc(sizeof(" + inner + ")); if (!__r) abort();\n"
    if hasArgs {
        let callArgs = this.params.paramArgListPrefixed("__e->")
        out = out + "    *__r = xc_" + nm + "(" + callArgs + ");\n"
        out = out + "    free(__e);\n"
    } else {
        out = out + "    *__r = xc_" + nm + "();\n"
    }
    out = out + "    return (void*)__r;\n}\n"
    out = out + "static xc_Future_t xc_spawn_" + nm + "(" + cSig(this.params) + ") {\n"
    if hasArgs {
        out = out + "    xc_aenv_" + nm + "_t* __e = (xc_aenv_" + nm + "_t*)malloc(sizeof(*__e)); if (!__e) abort();\n"
        out = out + "    " + this.params.envAssigns() + "\n"
        out = out + "    return xstd_future_spawn(xc_athunk_" + nm + ", (void*)__e);\n}\n"
    } else {
        out = out + "    return xstd_future_spawn(xc_athunk_" + nm + ", (void*)0);\n}\n"
    }
    return out
}

// ── runWithDelay { } capture machinery ───────────────────────────────────────
// The capturable set is the enclosing function's params + deps, recorded on the
// GCtx (capNames + capTypes-as-xtypes). A `runWithDelay` block captures, by
// value, the subset its body actually references; the worker thread runs the
// body after sleeping. The block lowers to a Future<Integer> (unit; await joins).
type Caps = { names: String[], xtypes: String[] }

// C type (without name) of a C-param segment, with a trailing space.
mapper String.segCtypeSpace() -> String {
    let cs = cSigSeg(this)
    let lw = lastWord(cs)
    return string_slice(cs, 0, string_len(cs) - string_len(lw))
}

// Build the capturable (name, xtype) lists from a C-param string + deps.
mapper String.buildCapNames(dlist: DepSpec[]) -> String[] {
    let out: String[] = []
    let n = string_len(this)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(this, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(this, start, i)
            if string_len(seg) > 0 { out = appendString(out, lastWord(seg)) }
            start = i + 1
        }
        i = i + 1
    }
    let j = 0
    let dn = depSpecLen(dlist)
    while j < dn { out = appendString(out, depSpecGet(dlist, j).name)  j = j + 1 }
    return out
}
mapper String.buildCapXTypes(dlist: DepSpec[]) -> String[] {
    let out: String[] = []
    let n = string_len(this)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(this, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(this, start, i)
            if string_len(seg) > 0 {
                let ct = seg.segCtypeSpace()
                out = appendString(out, string_slice(ct, 0, string_len(ct) - 1).ctypeToXName())
            }
            start = i + 1
        }
        i = i + 1
    }
    let j = 0
    let dn = depSpecLen(dlist)
    while j < dn { out = appendString(out, depSpecGet(dlist, j).ifaceName)  j = j + 1 }
    return out
}

// Does identifier `name` appear (as a value, not a `.field`) in toks[a, b)?
predicate Token[].identUsedIn(a: Integer, b: Integer, name: String) {
    let i = a
    while i < b {
        if this.kindAt(i) == 1 and this.textAt(i) == name {
            if i == a or this.kindAt(i - 1) != 107 { return true }   // 107 = '.'
        }
        i = i + 1
    }
    return false
}

// The subset of (capNames, capXTypes) referenced in the block toks[a, b).
mapper Token[].capturesIn(a: Integer, b: Integer, capNames: String[], capXTypes: String[]) -> Caps {
    let ns: String[] = []
    let xs: String[] = []
    let i = 0
    let n = stringArrLen(capNames)
    while i < n {
        let nm = stringArrGet(capNames, i)
        if this.identUsedIn(a, b, nm) {
            ns = appendString(ns, nm)
            xs = appendString(xs, stringArrGet(capXTypes, i))
        }
        i = i + 1
    }
    return Caps { names: ns, xtypes: xs }
}

// Parse `runWithDelay ( <ms> ) { body }` starting at the `runWithDelay` token.
type DelayParse = { msStart: Integer, msEnd: Integer, bodyStart: Integer, bodyEnd: Integer, endPos: Integer }
predicate Token[].isRunWithDelayAt(pos: Integer) {
    if this.kindAt(pos) != 1 { return false }
    if this.textAt(pos) != "runWithDelay" { return false }
    return this.kindAt(pos + 1) == 100
}
mapper Token[].parseDelayAt(pos: Integer) -> DelayParse {
    let msStart = pos + 2                       // past `runWithDelay` `(`
    // find the matching `)` of the ms argument
    let depth = 1
    let p = msStart
    while p < tokenArrLen(this) and depth > 0 {
        let kk = this.kindAt(p)
        if kk == 100 { depth = depth + 1 }
        if kk == 101 { depth = depth - 1 }
        if depth > 0 { p = p + 1 }
    }
    let msEnd = p                                // the `)`
    let bo = p + 1                               // the body `{`
    let close = this.matchBrace(bo)
    return DelayParse { msStart: msStart, msEnd: msEnd, bodyStart: bo + 1, bodyEnd: close, endPos: close + 1 }
}

// Lift every runWithDelay block in a body to a top-level worker + spawn helper.
mapper Program.hoistDelays(toks: Token[], tag: String, capNames: String[], capXTypes: String[]) -> String {
    let out = ""
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if toks.isRunWithDelayAt(i) {
            let dp = toks.parseDelayAt(i)
            let id = tag + "_" + int_to_string(i)
            let caps = toks.capturesIn(dp.bodyStart, dp.bodyEnd, capNames, capXTypes)
            let nc = stringArrLen(caps.names)
            // env struct: __ms plus each captured value
            out = out + "typedef struct { xc_integer_t __ms;"
            let c = 0
            while c < nc {
                out = out + " " + stringArrGet(caps.xtypes, c).xnameToCtype() + " " + stringArrGet(caps.names, c) + ";"
                c = c + 1
            }
            out = out + " } xc_delayenv_" + id + "_t;\n"
            // worker thunk: sleep, unpack captures, run body, return a unit result
            out = out + "static void* xc_delaythunk_" + id + "(void* __a) {\n"
            out = out + "    xc_delayenv_" + id + "_t* __e = (xc_delayenv_" + id + "_t*)__a;\n"
            out = out + "    xstd_sleep_ms(__e->__ms);\n"
            let bctx = ((this.newCtx()).withRet("void")).withTag(id)
            c = 0
            while c < nc {
                let nm = stringArrGet(caps.names, c)
                let xt = stringArrGet(caps.xtypes, c)
                out = out + "    " + xt.xnameToCtype() + " " + nm + " = __e->" + nm + ";\n"
                bctx = bctx.addSym(nm, xt)
                c = c + 1
            }
            out = out + genStmts(toks, dp.bodyStart, dp.bodyEnd, bctx)
            out = out + "    free(__e);\n"
            out = out + "    xc_integer_t* __r = (xc_integer_t*)malloc(sizeof(xc_integer_t)); if (!__r) abort(); *__r = 0;\n"
            out = out + "    return (void*)__r;\n}\n"
            // spawn helper: pack captures + ms, start the worker, return a Future
            out = out + "static xc_Future_t xc_delayspawn_" + id + "(xc_integer_t __ms"
            c = 0
            while c < nc {
                out = out + ", " + stringArrGet(caps.xtypes, c).xnameToCtype() + " " + stringArrGet(caps.names, c)
                c = c + 1
            }
            out = out + ") {\n"
            out = out + "    xc_delayenv_" + id + "_t* __e = (xc_delayenv_" + id + "_t*)malloc(sizeof(*__e)); if (!__e) abort();\n"
            out = out + "    __e->__ms = __ms;"
            c = 0
            while c < nc { let nm = stringArrGet(caps.names, c)  out = out + " __e->" + nm + " = " + nm + ";"  c = c + 1 }
            out = out + "\n    return xstd_future_spawn(xc_delaythunk_" + id + ", (void*)__e);\n}\n"
        }
        i = i + 1
    }
    return out
}
