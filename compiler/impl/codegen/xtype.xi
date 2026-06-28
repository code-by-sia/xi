// xc codegen — xtype/ctype machinery, async wrappers, captures, delays
// (part of the xc code generator — Program -> C99; spliced via codegen.xi)

mapper builtinForPath(path: String) -> String {
    match path {
        "system.stdout.writeln" -> "xc_stdout_writeln"
        "system.stdout.write"   -> "xc_stdout_write"
        "system.stderr.writeln" -> "xc_stderr_writeln"
        "system.stdin.readLine" -> "xc_stdin_readline"
        "system.process.exit"   -> "xc_process_exit"
        _ -> "0 /* unknown builtin */"
    }
}

// X type name -> C element type
mapper xnameToCtype(xname: String) -> String {
    if isPairXType(xname) { return "xc_pair_t" }
    if isFnXType(xname) { return "xc_fn_t" }
    match xname {
        "String"  -> "xc_string_t"
        "Number"  -> "xc_number_t"
        "Integer" -> "xc_integer_t"
        "Bool"    -> "xc_bool_t"
        "Char"    -> "xc_char_t"
        "Ptr"     -> "void*"
        "cstring" -> "const char*"
        _         -> "xc_" + xname + "_t"
    }
}

// ── Pair<A,B> xtype encoding ──────────────────────────────────────────────────
// "Pair(" + aXtype + ")(" + bXtype + ")". Balanced parens let nested element
// types (e.g. Pair<List_integer, List_integer> from partition/unzip) parse
// unambiguously; the C representation is always the uniform xc_pair_t.
predicate isPairXType(t: String) { return t.startsWith2("Pair(") }
mapper pairXtype(a: String, b: String) -> String => "Pair(" + a + ")(" + b + ")"

// Closure type encoding: "Fn(" + csv-of-param-xtypes + ")(" + ret-xtype + ")".
// Balanced parens (group 0 = params, group 1 = return) reuse the Pair extractor,
// so nested function/Pair types parse unambiguously; the C type is always xc_fn_t.
predicate isFnXType(t: String) { return t.startsWith2("Fn(") }
mapper fnXtype(paramsCsv: String, ret: String) -> String => "Fn(" + paramsCsv + ")(" + ret + ")"
mapper fnParamsX(t: String) -> String => pairElem(t, 0)
mapper fnRetX(t: String) -> String => pairElem(t, 1)

// Content of the `which`-th (0|1) balanced-paren group in a Pair xtype.
mapper pairElem(t: String, which: Integer) -> String {
    let n = string_len(t)
    let i = 0
    let group = 0
    while i < n {
        if string_char_at(t, i) == 40 {          // '(' opens a group
            let depth = 1
            let start = i + 1
            let j = start
            while j < n and depth > 0 {
                let c = string_char_at(t, j)
                if c == 40 { depth = depth + 1 }
                if c == 41 { depth = depth - 1 }
                if depth > 0 { j = j + 1 }
            }
            if group == which { return string_slice(t, start, j) }
            group = group + 1
            i = j + 1
        } else {
            i = i + 1
        }
    }
    return ""
}

// X type name -> array typedef suffix
mapper arrSuffixOf(xname: String) -> String {
    match xname {
        "String"  -> "string"
        "Number"  -> "number"
        "Integer" -> "integer"
        "Bool"    -> "bool"
        "Char"    -> "char"
        _         -> xname
    }
}

// array typedef suffix -> element X type name
mapper xnameFromArrSuffix(suf: String) -> String {
    match suf {
        "string"  -> "String"
        "number"  -> "Number"
        "integer" -> "Integer"
        "bool"    -> "Bool"
        "char"    -> "Char"
        _         -> suf
    }
}

// ── List<T> element-type helpers (xtype "List_<suffix>") ──────────
predicate isListXType(typ: String) { return typ.startsWith2("List_") }
mapper listElemCtype(typ: String) -> String {
    return xnameToCtype(xnameFromArrSuffix(string_slice(typ, 5, string_len(typ))))
}
mapper listElemXName(typ: String) -> String {
    return xnameFromArrSuffix(string_slice(typ, 5, string_len(typ)))
}

// ── Set<T> element-type helpers (xtype "Set_<suffix>") ──────────
predicate isSetXType(typ: String) { return typ.startsWith2("Set_") }
mapper setElemCtype(typ: String) -> String {
    return xnameToCtype(xnameFromArrSuffix(string_slice(typ, 4, string_len(typ))))
}
mapper setElemXName(typ: String) -> String {
    return xnameFromArrSuffix(string_slice(typ, 4, string_len(typ)))
}
mapper setElemSuffix(typ: String) -> String {
    return string_slice(typ, 4, string_len(typ))
}
// `1` if the element/key ctype is a String (hashed/compared by content), else `0`.
mapper strFlagFor(ctype: String) -> String {
    if ctype == "xc_string_t" { return "1" }
    return "0"
}

// ── Stack<T> / Queue<T> / SortedQueue<T> element helpers ──────────────────────
// xtypes "Stack_<suf>" (6), "Queue_<suf>" (6), "SortedQueue_<suf>" (12).
predicate isStackXType(typ: String) { return typ.startsWith2("Stack_") }
mapper stackElemSuffix(typ: String) -> String { return string_slice(typ, 6, string_len(typ)) }
mapper stackElemCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(stackElemSuffix(typ))) }
mapper stackElemXName(typ: String) -> String { return xnameFromArrSuffix(stackElemSuffix(typ)) }

predicate isQueueXType(typ: String) { return typ.startsWith2("Queue_") }
mapper queueElemSuffix(typ: String) -> String { return string_slice(typ, 6, string_len(typ)) }
mapper queueElemCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(queueElemSuffix(typ))) }
mapper queueElemXName(typ: String) -> String { return xnameFromArrSuffix(queueElemSuffix(typ)) }

predicate isSortedQueueXType(typ: String) { return typ.startsWith2("SortedQueue_") }
mapper sqElemSuffix(typ: String) -> String { return string_slice(typ, 12, string_len(typ)) }
mapper sqElemCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(sqElemSuffix(typ))) }
mapper sqElemXName(typ: String) -> String { return xnameFromArrSuffix(sqElemSuffix(typ)) }

// Min-heap comparison kind for SortedQueue from the element ctype:
// 1 = number (double), 2 = String (by content), 0 = integer/char/bool.
mapper pqCmpKind(ec: String) -> String {
    if ec == "xc_number_t" { return "1" }
    if ec == "xc_string_t" { return "2" }
    return "0"
}

// ── Future<T> helpers (async / await) ────────────────────────────────────────
// xtype "Future_<suf>"; C type xc_Future_<suf>_t (== xc_Future_t).
predicate isFutureXType(typ: String) { return typ.startsWith2("Future_") }
mapper futureInnerSuffix(typ: String) -> String { return string_slice(typ, 7, string_len(typ)) }
mapper futureInnerXName(typ: String) -> String { return xnameFromArrSuffix(futureInnerSuffix(typ)) }
mapper futureInnerCtype(typ: String) -> String { return xnameToCtype(futureInnerXName(typ)) }
// Is a C return type a Future (`xc_Future_<suf>_t`)?
predicate isFutureCtype(ct: String) { return ct.startsWith2("xc_Future_") }
// Inner C type of a Future C type: xc_Future_integer_t -> xc_integer_t.
mapper futureCtypeInner(ct: String) -> String {
    let mid = string_slice(ct, 10, string_len(ct) - 2)   // strip "xc_Future_" .. "_t"
    return "xc_" + mid + "_t"
}
// Future xtype for an inner C type: xc_integer_t -> "Future_integer".
mapper futureXtypeFor(innerCtype: String) -> String { return "Future_" + ctypeSuffix(innerCtype) }

// A free function auto-spawns (its calls run on a worker and yield a Future)
// when marked `async`. A `-> Future<T>` return type is NOT auto-spawn: such a
// function returns a future value it built itself (e.g. from an async call or
// `runWithDelay`), which the caller can `await` directly.
predicate isAsyncFuncC(prog: Program, name: String) {
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let fs = funcSpecGet(prog.functions, i)
        if fs.name == name { return fs.isAsync }
        i = i + 1
    }
    return false
}
// The value an async function's body actually returns (the inner T), as a C type.
mapper asyncInnerCtype(fs: FuncSpec) -> String {
    if isFutureCtype(fs.retCtype) { return futureCtypeInner(fs.retCtype) }
    return fs.retCtype
}
// "T a, U b" -> "T a; U b;" (struct fields for the captured-args env).
mapper cFields(params: String) -> String {
    let out = ""
    let n = string_len(params)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(params, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(params, start, i)
            if string_len(seg) > 0 { out = out + cSigSeg(seg) + "; " }
            start = i + 1
        }
        i = i + 1
    }
    return out
}
// "T a, U b" -> "__e->a = a; __e->b = b; " (copy args into the env struct).
mapper envAssigns(params: String) -> String {
    let out = ""
    let n = string_len(params)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(params, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(params, start, i)
            if string_len(seg) > 0 { let nm = lastWord(seg)  out = out + "__e->" + nm + " = " + nm + "; " }
            start = i + 1
        }
        i = i + 1
    }
    return out
}

// For an async free function `fs`, emit the captured-args env struct, the worker
// thunk (runs the body, mallocs the T result), and `xc_spawn_<name>(params)`
// which packs the args and returns a Future. The call site calls xc_spawn_<name>.
mapper emitAsyncWrapper(prog: Program, fs: FuncSpec) -> String {
    let inner = cTy(asyncInnerCtype(fs))
    let nm = fs.name
    let args = paramArgList(fs.params)
    let hasArgs = string_len(fs.params) > 0
    let out = ""
    if hasArgs { out = out + "typedef struct { " + cFields(fs.params) + "} xc_aenv_" + nm + "_t;\n" }
    out = out + "static void* xc_athunk_" + nm + "(void* __p) {\n"
    if hasArgs {
        out = out + "    xc_aenv_" + nm + "_t* __e = (xc_aenv_" + nm + "_t*)__p;\n"
    } else {
        out = out + "    (void)__p;\n"
    }
    out = out + "    " + inner + "* __r = (" + inner + "*)malloc(sizeof(" + inner + ")); if (!__r) abort();\n"
    if hasArgs {
        let callArgs = paramArgListPrefixed(fs.params, "__e->")
        out = out + "    *__r = xc_" + nm + "(" + callArgs + ");\n"
        out = out + "    free(__e);\n"
    } else {
        out = out + "    *__r = xc_" + nm + "();\n"
    }
    out = out + "    return (void*)__r;\n}\n"
    out = out + "static xc_Future_t xc_spawn_" + nm + "(" + cSig(fs.params) + ") {\n"
    if hasArgs {
        out = out + "    xc_aenv_" + nm + "_t* __e = (xc_aenv_" + nm + "_t*)malloc(sizeof(*__e)); if (!__e) abort();\n"
        out = out + "    " + envAssigns(fs.params) + "\n"
        out = out + "    return xstd_future_spawn(xc_athunk_" + nm + ", (void*)__e);\n}\n"
    } else {
        out = out + "    return xstd_future_spawn(xc_athunk_" + nm + ", (void*)0);\n}\n"
    }
    return out
}
// Like paramArgList but each name is prefixed (e.g. "__e->a, __e->b").
mapper paramArgListPrefixed(cparams: String, pfx: String) -> String {
    let n = string_len(cparams)
    if n == 0 { return "" }
    let out = ""
    let start = 0
    let i = 0
    let first = true
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(cparams, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(cparams, start, i)
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

// ── runWithDelay { } capture machinery ───────────────────────────────────────
// The capturable set is the enclosing function's params + deps, recorded on the
// GCtx (capNames + capTypes-as-xtypes). A `runWithDelay` block captures, by
// value, the subset its body actually references; the worker thread runs the
// body after sleeping. The block lowers to a Future<Integer> (unit; await joins).
type Caps = { names: String[], xtypes: String[] }

// C type (without name) of a C-param segment, with a trailing space.
mapper segCtypeSpace(seg: String) -> String {
    let cs = cSigSeg(seg)
    let lw = lastWord(cs)
    return string_slice(cs, 0, string_len(cs) - string_len(lw))
}

// Build the capturable (name, xtype) lists from a C-param string + deps.
mapper buildCapNames(params: String, dlist: DepSpec[]) -> String[] {
    let out: String[] = []
    let n = string_len(params)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(params, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(params, start, i)
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
mapper buildCapXTypes(params: String, dlist: DepSpec[]) -> String[] {
    let out: String[] = []
    let n = string_len(params)
    let start = 0
    let i = 0
    while i <= n {
        let atEnd = i == n
        let isComma = false
        if not atEnd { if string_char_at(params, i) == 44 { isComma = true } }
        if atEnd or isComma {
            let seg = string_slice(params, start, i)
            if string_len(seg) > 0 {
                let ct = segCtypeSpace(seg)
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
predicate identUsedIn(toks: Token[], a: Integer, b: Integer, name: String) {
    let i = a
    while i < b {
        if toks.kindAt(i) == 1 and toks.textAt(i) == name {
            if i == a or toks.kindAt(i - 1) != 107 { return true }   // 107 = '.'
        }
        i = i + 1
    }
    return false
}

// The subset of (capNames, capXTypes) referenced in the block toks[a, b).
mapper capturesIn(toks: Token[], a: Integer, b: Integer, capNames: String[], capXTypes: String[]) -> Caps {
    let ns: String[] = []
    let xs: String[] = []
    let i = 0
    let n = stringArrLen(capNames)
    while i < n {
        let nm = stringArrGet(capNames, i)
        if identUsedIn(toks, a, b, nm) {
            ns = appendString(ns, nm)
            xs = appendString(xs, stringArrGet(capXTypes, i))
        }
        i = i + 1
    }
    return Caps { names: ns, xtypes: xs }
}

// Parse `runWithDelay ( <ms> ) { body }` starting at the `runWithDelay` token.
type DelayParse = { msStart: Integer, msEnd: Integer, bodyStart: Integer, bodyEnd: Integer, endPos: Integer }
predicate isRunWithDelayAt(toks: Token[], pos: Integer) {
    if toks.kindAt(pos) != 1 { return false }
    if toks.textAt(pos) != "runWithDelay" { return false }
    return toks.kindAt(pos + 1) == 100
}
mapper parseDelayAt(toks: Token[], pos: Integer) -> DelayParse {
    let msStart = pos + 2                       // past `runWithDelay` `(`
    // find the matching `)` of the ms argument
    let depth = 1
    let p = msStart
    while p < tokenArrLen(toks) and depth > 0 {
        let kk = toks.kindAt(p)
        if kk == 100 { depth = depth + 1 }
        if kk == 101 { depth = depth - 1 }
        if depth > 0 { p = p + 1 }
    }
    let msEnd = p                                // the `)`
    let bo = p + 1                               // the body `{`
    let close = toks.matchBrace(bo)
    return DelayParse { msStart: msStart, msEnd: msEnd, bodyStart: bo + 1, bodyEnd: close, endPos: close + 1 }
}

// Lift every runWithDelay block in a body to a top-level worker + spawn helper.
mapper hoistDelays(prog: Program, toks: Token[], tag: String, capNames: String[], capXTypes: String[]) -> String {
    let out = ""
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if isRunWithDelayAt(toks, i) {
            let dp = parseDelayAt(toks, i)
            let id = tag + "_" + int_to_string(i)
            let caps = capturesIn(toks, dp.bodyStart, dp.bodyEnd, capNames, capXTypes)
            let nc = stringArrLen(caps.names)
            // env struct: __ms plus each captured value
            out = out + "typedef struct { xc_integer_t __ms;"
            let c = 0
            while c < nc {
                out = out + " " + xnameToCtype(stringArrGet(caps.xtypes, c)) + " " + stringArrGet(caps.names, c) + ";"
                c = c + 1
            }
            out = out + " } xc_delayenv_" + id + "_t;\n"
            // worker thunk: sleep, unpack captures, run body, return a unit result
            out = out + "static void* xc_delaythunk_" + id + "(void* __a) {\n"
            out = out + "    xc_delayenv_" + id + "_t* __e = (xc_delayenv_" + id + "_t*)__a;\n"
            out = out + "    xstd_sleep_ms(__e->__ms);\n"
            let bctx = ((prog.newCtx()).withRet("void")).withTag(id)
            c = 0
            while c < nc {
                let nm = stringArrGet(caps.names, c)
                let xt = stringArrGet(caps.xtypes, c)
                out = out + "    " + xnameToCtype(xt) + " " + nm + " = __e->" + nm + ";\n"
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
                out = out + ", " + xnameToCtype(stringArrGet(caps.xtypes, c)) + " " + stringArrGet(caps.names, c)
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

// ── Map<K,V> key/value helpers (xtype "Map_<ksuf>_<vsuf>") ──────────
// The key is always a primitive/String suffix, so its boundary is unambiguous.
predicate isMapXType(typ: String) { return typ.startsWith2("Map_") }
mapper mapKeySuffix(typ: String) -> String {
    let rest = string_slice(typ, 4, string_len(typ))   // "<ksuf>_<vsuf>"
    if rest.startsWith2("integer_") { return "integer" }
    if rest.startsWith2("number_")  { return "number" }
    if rest.startsWith2("bool_")    { return "bool" }
    if rest.startsWith2("string_")  { return "string" }
    if rest.startsWith2("char_")    { return "char" }
    return ""
}
mapper mapValSuffix(typ: String) -> String {
    let rest = string_slice(typ, 4, string_len(typ))
    let k = mapKeySuffix(typ)
    return string_slice(rest, string_len(k) + 1, string_len(rest))
}
mapper mapKeyCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(mapKeySuffix(typ))) }
mapper mapValCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(mapValSuffix(typ))) }
mapper mapValXName(typ: String) -> String { return xnameFromArrSuffix(mapValSuffix(typ)) }
mapper mapKeyXName(typ: String) -> String { return xnameFromArrSuffix(mapKeySuffix(typ)) }

// Primitive token kind -> C type (for type annotations in let statements)
mapper primCtypeK(k: Integer) -> String {
    match k {
        260 -> "xc_number_t"
        261 -> "xc_integer_t"
        262 -> "xc_bool_t"
        263 -> "xc_string_t"
        264 -> "xc_char_t"
        265 -> "void"
        266 -> "xc_size_t"
        267 -> "const char*"
        269 -> "void*"
        _   -> ""
    }
}

// Read a type expression from a token stream and return its C type string.
mapper typeCtypeOf(toks: Token[], start: Integer) -> String {
    let k = toks.kindAt(start)
    let base = ""
    let p = start
    let pc = primCtypeK(k)
    if string_len(pc) > 0 {
        base = pc
        p = start + 1
    } else {
        if k == 1 {
            base = "xc_" + toks.textAt(start) + "_t"
            p = start + 1
        } else {
            return "void*"
        }
    }
    let suf = ctypeSuffix(base)
    let result = base
    let cont = true
    while cont {
        let pk = toks.kindAt(p)
        if pk == 127 {
            result = "xc_opt_" + suf + "_t"
            p = p + 1
        } else {
            if pk == 126 {
                result = "xc_res_" + suf + "_t"
                p = p + 1
            } else {
            if pk == 104 and toks.kindAt(p + 1) == 105 {
                result = "xc_arr_" + suf + "_t"
                p = p + 2
            } else {
                cont = false
            }
            }
        }
    }
    return result
}

// ── parameter seeding (parse the C param string) ──────────────────
mapper addParamSym(ctx: GCtx, seg: String) -> GCtx {
    let n = string_len(seg)
    let s = 0
    while s < n and string_char_at(seg, s) == 32 { s = s + 1 }
    let lastSp = 0 - 1
    let i = s
    while i < n {
        if string_char_at(seg, i) == 32 { lastSp = i }
        i = i + 1
    }
    if lastSp < 0 { return ctx }
    let ctype = string_slice(seg, s, lastSp)
    let name  = string_slice(seg, lastSp + 1, n)
    return ctx.addSym(name, (ctx.prog).resolveX(ctype.ctypeToXName()))
}

mapper seedParams(ctx: GCtx, cparams: String) -> GCtx {
    let result = ctx
    let n = string_len(cparams)
    if n == 0 { return result }
    let start = 0
    let i = 0
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(cparams, i) }
        if atEnd or c == 44 {
            let seg = string_slice(cparams, start, i)
            result = addParamSym(result, seg)
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return result
}

// Coerce a C expression to a string value for concatenation. (Written as a
// tabular `decision` — the compiler dogfooding its own decision-table feature:
// the `typ` column selects the wrapper, and the output expressions build on the
// `code` input.)
decision toStrC {
    in  code: String
    in  typ:  String
    out wrapped: String
    hit first
    | - | "String"  => code |
    | - | "Integer" => "xc_integer_to_string(" + code + ")" |
    | - | "Bool"    => "xc_bool_to_string(" + code + ")" |
    | - | "Number"  => "xc_number_to_string(" + code + ")" |
    | - | -         => "xc_number_to_string((xc_number_t)(" + code + "))" |
}

