// xc code generator — Program -> C99
// ── Expression / statement codegen from token stream ─────────────
// Converts a Token[] body into C code string.

// ── Expression / statement code generator ────────────────────────
// A recursive-descent generator that walks body tokens and emits C,
// tracking a small symbol table for type-aware dispatch.

// `owned` = the expression yields a freshly-owned heap value (rc 1) the
// consumer must release, vs a borrowed/aliased value (variable, field,
// literal) it must not. Drives ARC retain/release insertion (Phase 3).
type ExprRes = { code: String, pos: Integer, xtyp: String, owned: Bool }
type GArgs   = { code: String, pos: Integer, firstRaw: String }

type GCtx = {
    prog:     Program,
    symNames: String[],
    symTypes: String[],
    depNames: String[],
    depTypes: String[],
    retCtype: String,
    fnTag:    String,       // mangled name of the enclosing fn (for catch helpers)
    selfClass: String,      // enclosing class name in a method body ("" otherwise)
    capNames: String[],     // params+deps capturable by `runWithDelay { }` blocks
    capTypes: String[]      // their C types (index-matched with capNames)
}

type StmtRes = { code: String, ctx: GCtx, pos: Integer }

// ── token access helpers ─────────────────────────────────────────
mapper gkind(toks: Token[], i: Integer) -> Integer => tokenArrGet(toks, i).kind
mapper gtext(toks: Token[], i: Integer) -> String => tokenArrGet(toks, i).text

// Escape a string for embedding in a C string literal (backslash and quote).
mapper cEscape(s: String) -> String {
    let n = string_len(s)
    let out = ""
    let runStart = 0
    let i = 0
    while i < n {
        let c = string_char_at(s, i)
        if c == 34 or c == 92 {     // " or backslash
            out = out + string_slice(s, runStart, i) + "\\" + string_slice(s, i, i + 1)
            runStart = i + 1
        }
        i = i + 1
    }
    return out + string_slice(s, runStart, n)
}

// Test build? `xi test` sets XC_TEST=1; in test mode the synthesized main runs
// the `test` cases and DI prefers `module Test` bindings over `module App`.
predicate inTestMode() { return string_len(get_env("XC_TEST", "")) > 0 }

// index of the } matching the { at openIdx
mapper matchBrace(toks: Token[], openIdx: Integer) -> Integer {
    let depth = 0
    let p = openIdx
    let n = tokenArrLen(toks)
    let result = openIdx
    let cont = true
    while cont and p < n {
        let k = gkind(toks, p)
        if k == 102 {
            depth = depth + 1
        } else {
            if k == 103 {
                depth = depth - 1
                if depth == 0 {
                    result = p
                    cont = false
                }
            }
        }
        p = p + 1
    }
    return result
}

// ── context helpers ───────────────────────────────────────────────
creator mkGCtx(prog: Program) -> GCtx => GCtx { prog: prog, symNames: [], symTypes: [], depNames: [], depTypes: [], retCtype: "", fnTag: "", selfClass: "", capNames: [], capTypes: [] }

mapper withRet(ctx: GCtx, ret: String) -> GCtx {
    return GCtx {
        prog: ctx.prog, symNames: ctx.symNames, symTypes: ctx.symTypes,
        depNames: ctx.depNames, depTypes: ctx.depTypes, retCtype: ret, fnTag: ctx.fnTag,
        selfClass: ctx.selfClass, capNames: ctx.capNames, capTypes: ctx.capTypes
    }
}

mapper withTag(ctx: GCtx, tag: String) -> GCtx {
    return GCtx {
        prog: ctx.prog, symNames: ctx.symNames, symTypes: ctx.symTypes,
        depNames: ctx.depNames, depTypes: ctx.depTypes, retCtype: ctx.retCtype, fnTag: tag,
        selfClass: ctx.selfClass, capNames: ctx.capNames, capTypes: ctx.capTypes
    }
}

// Mark the enclosing class so unqualified calls to sibling methods resolve to
// `xc_<Class>_<name>_impl(self, ...)`.
mapper withSelfClass(ctx: GCtx, cls: String) -> GCtx {
    return GCtx {
        prog: ctx.prog, symNames: ctx.symNames, symTypes: ctx.symTypes,
        depNames: ctx.depNames, depTypes: ctx.depTypes, retCtype: ctx.retCtype, fnTag: ctx.fnTag,
        selfClass: cls, capNames: ctx.capNames, capTypes: ctx.capTypes
    }
}

// Record the enclosing function's params+deps as the set capturable by a
// `runWithDelay { }` block (so its worker thread can see them by value).
mapper withCaps(ctx: GCtx, names: String[], types: String[]) -> GCtx {
    return GCtx {
        prog: ctx.prog, symNames: ctx.symNames, symTypes: ctx.symTypes,
        depNames: ctx.depNames, depTypes: ctx.depTypes, retCtype: ctx.retCtype, fnTag: ctx.fnTag,
        selfClass: ctx.selfClass, capNames: names, capTypes: types
    }
}

mapper addSym(ctx: GCtx, name: String, typ: String) -> GCtx {
    return GCtx {
        prog: ctx.prog,
        symNames: appendString(ctx.symNames, name),
        symTypes: appendString(ctx.symTypes, typ),
        depNames: ctx.depNames,
        depTypes: ctx.depTypes,
        retCtype: ctx.retCtype,
        fnTag: ctx.fnTag,
        selfClass: ctx.selfClass,
        capNames: ctx.capNames,
        capTypes: ctx.capTypes
    }
}

mapper addDep(ctx: GCtx, name: String, typ: String) -> GCtx {
    return GCtx {
        prog: ctx.prog,
        symNames: ctx.symNames,
        symTypes: ctx.symTypes,
        depNames: appendString(ctx.depNames, name),
        depTypes: appendString(ctx.depTypes, typ),
        retCtype: ctx.retCtype,
        fnTag: ctx.fnTag,
        selfClass: ctx.selfClass,
        capNames: ctx.capNames,
        capTypes: ctx.capTypes
    }
}

mapper lookupVar(ctx: GCtx, name: String) -> String {
    let i = 0
    let n = stringArrLen(ctx.symNames)
    while i < n {
        if stringArrGet(ctx.symNames, i) == name {
            return stringArrGet(ctx.symTypes, i)
        }
        i = i + 1
    }
    return ""
}

predicate isDepNameC(ctx: GCtx, name: String) {
    let i = 0
    let n = stringArrLen(ctx.depNames)
    while i < n {
        if stringArrGet(ctx.depNames, i) == name { return true }
        i = i + 1
    }
    return false
}

mapper depTypeOf(ctx: GCtx, name: String) -> String {
    let i = 0
    let n = stringArrLen(ctx.depNames)
    while i < n {
        if stringArrGet(ctx.depNames, i) == name {
            return stringArrGet(ctx.depTypes, i)
        }
        i = i + 1
    }
    return ""
}

// ── name/type predicates over the program ─────────────────────────
mapper ctypeToXName(ctype: String) -> String {
    if isFnXType(ctype) { return ctype }    // Fn(...)/Pair(...) carry their own
    if isPairXType(ctype) { return ctype }  // signature; they're already xtypes
    match ctype {
        "xc_string_t"  -> "String"
        "xc_number_t"  -> "Number"
        "xc_integer_t" -> "Integer"
        "xc_bool_t"    -> "Bool"
        "xc_char_t"    -> "Char"
        "xc_size_t"    -> "Size"
        "void*"        -> "Ptr"
        "const char*"  -> "cstring"
        _ -> {
            // strip leading "xc_" and trailing "_t"
            if string_len(ctype) > 5 { return string_slice(ctype, 3, string_len(ctype) - 2) }
            return ""
        }
    }
}

// Resolve a refined type name to its underlying primitive X-type name.
// e.g. NonEmpty -> String, Age -> Number. Compounds/interfaces pass through.
mapper resolveX(prog: Program, xname: String) -> String {
    if xname == "String"  { return "String" }
    if xname == "Number"  { return "Number" }
    if xname == "Integer" { return "Integer" }
    if xname == "Bool"    { return "Bool" }
    if xname == "Char"    { return "Char" }
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == xname {
            if ts.isCompound {
                return xname
            }
            return ctypeToXName(ts.baseCtype)
        }
        i = i + 1
    }
    return xname
}

predicate isModuleNameC(prog: Program, name: String) {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        if moduleSpecGet(prog.modules, i).name == name { return true }
        i = i + 1
    }
    return false
}

predicate isFuncNameC(prog: Program, name: String) {
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        if funcSpecGet(prog.functions, i).name == name { return true }
        i = i + 1
    }
    return false
}

predicate isAtomNameC(prog: Program, name: String) {
    let i = 0
    let n = atomSpecLen(prog.atoms)
    while i < n {
        if atomSpecGet(prog.atoms, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper atomStateTypeName(prog: Program, name: String) -> String {
    let i = 0
    let n = atomSpecLen(prog.atoms)
    while i < n {
        let a = atomSpecGet(prog.atoms, i)
        if a.name == name { return a.stateTypeName }
        i = i + 1
    }
    return ""
}

predicate isMachineTypeC(prog: Program, name: String) {
    let i = 0
    let n = machineSpecLen(prog.machines)
    while i < n {
        if machineSpecGet(prog.machines, i).name == name { return true }
        i = i + 1
    }
    return false
}

// Is `name` (an X type name) a declared typed `event`?
predicate isEventTypeC(prog: Program, name: String) {
    let i = 0
    let n = stringArrLen(prog.eventTypes)
    while i < n {
        if stringArrGet(prog.eventTypes, i) == name { return true }
        i = i + 1
    }
    return false
}

// Is `name` a declared compound (struct-like) type?
predicate isCompoundTypeC(prog: Program, name: String) {
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == name and ts.isCompound { return true }
        i = i + 1
    }
    return false
}

// ── Sum / algebraic types ─────────────────────────────────────────
predicate isSumTypeC(prog: Program, name: String) {
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == name and ts.isSum { return true }
        i = i + 1
    }
    return false
}

// The sum type that owns variant `vname` (or "" if none). Variant names must be
// globally unique across sum types.
mapper sumOfVariant(prog: Program, vname: String) -> String {
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.isSum {
            let vi = 0
            let vn = stringArrLen(ts.variants)
            while vi < vn {
                let v = stringArrGet(ts.variants, vi)
                let bar = findChar(v, 124)            // '|'
                if string_slice(v, 0, bar) == vname { return ts.name }
                vi = vi + 1
            }
        }
        i = i + 1
    }
    return ""
}

predicate isVariantNameC(prog: Program, vname: String) => string_len(sumOfVariant(prog, vname)) > 0

// The "f1:ct1,f2:ct2" field string for a variant ("" if it carries no payload).
mapper variantFieldsC(prog: Program, sumName: String, vname: String) -> String {
    let ts = findTypeSpec(prog, sumName)
    let vi = 0
    let vn = stringArrLen(ts.variants)
    while vi < vn {
        let v = stringArrGet(ts.variants, vi)
        let bar = findChar(v, 124)
        if string_slice(v, 0, bar) == vname { return string_slice(v, bar + 1, string_len(v)) }
        vi = vi + 1
    }
    return ""
}

// "f1:ct1,f2:ct2" -> "ct1 f1; ct2 f2; " for a C struct body.
mapper sumFieldsToC(fstr: String) -> String {
    let out = ""
    let n = string_len(fstr)
    if n == 0 { return out }
    let start = 0
    let i = 0
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(fstr, i) }
        if atEnd or c == 44 {                          // ','
            let seg = string_slice(fstr, start, i)
            let colon = findChar(seg, 58)              // ':'
            let fname = string_slice(seg, 0, colon)
            let fct = string_slice(seg, colon + 1, string_len(seg))
            out = out + fct + " " + fname + "; "
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return out
}

// std/web's handler model is active when at least one class implements
// WebRequestHandler (controllers are auto-registered — no explicit bind needed).
predicate webEnabled(prog: Program) {
    if not isInterface(prog, "WebRequestHandler") { return false }
    return stringArrLen(implementorsOf(prog, "WebRequestHandler")) > 0
}

// Does a token body reference threading (a `parallel` block or the `thread`
// facility)? Used to decide whether to derive codecs for channel payloads.
predicate tokensUseThread(toks: Token[]) {
    let i = 0
    let n = tokenArrLen(toks)
    while i < n {
        let t = tokenArrGet(toks, i)
        if t.kind == 1 {
            if t.text == "parallel" { return true }
            if t.text == "thread" { return true }
        }
        i = i + 1
    }
    return false
}

predicate usesThreads(prog: Program) {
    if tokensUseThread(prog.entrySpec.bodyTokens) { return true }
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        if tokensUseThread(funcSpecGet(prog.functions, i).bodyTokens) { return true }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            if tokensUseThread(methodSpecGet(cs.methList, mi).bodyTokens) { return true }
            mi = mi + 1
        }
        ci = ci + 1
    }
    return false
}

// A JSON codec (xc_tojson_/xc_fromjson_) is emitted for this X type: every event
// type, plus (when web or threading is in use, so channels can carry structured
// payloads) every compound type.
// Any `bind I -> readConfig("...")` in the program?
predicate usesConfig(prog: Program) {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            if string_len(bindSpecGet(mod.bindings, j).configPath) > 0 { return true }
            j = j + 1
        }
        i = i + 1
    }
    return false
}

// The config file path bound to interface `ifn`, or "" if it isn't config-backed.
mapper configPathFor(prog: Program, ifn: String) -> String {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    let found = ""
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let isTest = (mod.name == "Test")
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.ifaceName == ifn and string_len(b.configPath) > 0 {
                if isTest and inTestMode() { return b.configPath }   // Test config wins under XC_TEST
                if not isTest { found = b.configPath }
            }
            j = j + 1
        }
        i = i + 1
    }
    return found
}

// Does any function/entry/test/method body call `readConfig<T>(...)`?
predicate tokensHaveIdent(toks: Token[], name: String) {
    let i = 0
    let n = tokenArrLen(toks)
    while i < n {
        let t = tokenArrGet(toks, i)
        if t.kind == 1 and t.text == name { return true }
        i = i + 1
    }
    return false
}
predicate progUsesReadConfig(prog: Program) {
    if tokensHaveIdent(prog.entrySpec.bodyTokens, "readConfig") { return true }
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n { if tokensHaveIdent(funcSpecGet(prog.functions, i).bodyTokens, "readConfig") { return true }  i = i + 1 }
    let ti = 0
    let tn = funcSpecLen(prog.tests)
    while ti < tn { if tokensHaveIdent(funcSpecGet(prog.tests, ti).bodyTokens, "readConfig") { return true }  ti = ti + 1 }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn { if tokensHaveIdent(methodSpecGet(cs.methList, mi).bodyTokens, "readConfig") { return true }  mi = mi + 1 }
        ci = ci + 1
    }
    return false
}

// Does any body use a `<json> as T` decode? (an `as` token, kind 209, inside an
// expression body — module `bind … as` is parsed separately, never in a body).
predicate tokensHaveKind(toks: Token[], k: Integer) {
    let i = 0
    let n = tokenArrLen(toks)
    while i < n { if tokenArrGet(toks, i).kind == k { return true }  i = i + 1 }
    return false
}
predicate progUsesAsDecode(prog: Program) {
    if tokensHaveKind(prog.entrySpec.bodyTokens, 209) { return true }
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n { if tokensHaveKind(funcSpecGet(prog.functions, i).bodyTokens, 209) { return true }  i = i + 1 }
    let ti = 0
    let tn = funcSpecLen(prog.tests)
    while ti < tn { if tokensHaveKind(funcSpecGet(prog.tests, ti).bodyTokens, 209) { return true }  ti = ti + 1 }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn { if tokensHaveKind(methodSpecGet(cs.methList, mi).bodyTokens, 209) { return true }  mi = mi + 1 }
        ci = ci + 1
    }
    return false
}
predicate codecsEnabled(prog: Program) {
    return webEnabled(prog) or usesThreads(prog) or usesConfig(prog) or progUsesReadConfig(prog) or progUsesAsDecode(prog)
}

predicate hasCodec(prog: Program, xn: String) {
    if isEventTypeC(prog, xn) { return true }
    if isCompoundTypeC(prog, xn) and codecsEnabled(prog) { return true }
    return false
}

// The X type name of a listener method's first parameter (the event it handles),
// extracted from the C param string "xc_OrderPaid_t e[, ...]".
mapper firstParamXType(params: String) -> String {
    let n = string_len(params)
    let sp = 0
    while sp < n and string_char_at(params, sp) != 32 { sp = sp + 1 }
    if sp == 0 { return "" }
    return ctypeToXName(string_slice(params, 0, sp))
}

mapper machineStateIndex(m: MachineSpec, name: String) -> Integer {
    let i = 0
    let n = stringArrLen(m.states)
    while i < n {
        if stringArrGet(m.states, i) == name { return i }
        i = i + 1
    }
    return 0 - 1
}

// Build a C condition over comma-joined state names: (self.__state == i) || ...
mapper machineStateCond(m: MachineSpec, csv: String) -> String {
    let cond = ""
    let start = 0
    let i = 0
    let n = string_len(csv)
    while i <= n {
        let isSep = false
        if i == n { isSep = true } else { if string_char_at(csv, i) == 44 { isSep = true } }
        if isSep {
            let nm = string_slice(csv, start, i)
            if string_len(nm) > 0 {
                if string_len(cond) > 0 { cond = cond + " || " }
                cond = cond + "(self.__state == " + int_to_string(machineStateIndex(m, nm)) + ")"
            }
            start = i + 1
        }
        i = i + 1
    }
    if string_len(cond) == 0 { cond = "0" }
    return cond
}

// The C type of a machine `data` field ("" if absent), from "name:ctype" pairs.
mapper dataFieldCtype(m: MachineSpec, fname: String) -> String {
    let i = 0
    let n = stringArrLen(m.dataFields)
    while i < n {
        let f = stringArrGet(m.dataFields, i)
        let colon = findChar(f, 58)
        if string_slice(f, 0, colon) == fname { return string_slice(f, colon + 1, string_len(f)) }
        i = i + 1
    }
    return ""
}

// An empty array literal `[]` lowers to an untyped `{0}`; in a typed assignment
// (machine data init/update) cast it to the field's type so C accepts it.
mapper castEmptyArr(m: MachineSpec, fname: String, e: ExprRes) -> String {
    if e.xtyp == "emptyarr" {
        let fct = dataFieldCtype(m, fname)
        if string_len(fct) > 0 { return "(" + fct + "){0}" }
    }
    return e.code
}

// True if `name` appears in a comma-joined list of state names.
predicate csvHasState(csv: String, name: String) {
    let start = 0
    let i = 0
    let n = string_len(csv)
    while i <= n {
        let isSep = i == n
        if not isSep { if string_char_at(csv, i) == 44 { isSep = true } }
        if isSep {
            if string_slice(csv, start, i) == name { return true }
            start = i + 1
        }
        i = i + 1
    }
    return false
}

// Static validation of every `machine` graph. Unknown state references are
// errors; unreachable states and dead ends (a non-terminal state with no
// outgoing transition) are warnings.
consumer checkMachines(prog: Program) {
    let mi = 0
    let mn = machineSpecLen(prog.machines)
    while mi < mn {
        let m = machineSpecGet(prog.machines, mi)
        let trn = machineTransLen(m.transitions)
        if machineStateIndex(m, m.initial) < 0 {
            diag_error(0, "machine " + m.name + ": initial state '" + m.initial + "' is not declared")
        }
        let ti = 0
        while ti < stringArrLen(m.terminals) {
            let tnm = stringArrGet(m.terminals, ti)
            if machineStateIndex(m, tnm) < 0 {
                diag_error(0, "machine " + m.name + ": terminal '" + tnm + "' is not declared")
            }
            ti = ti + 1
        }
        // transition source/target states must exist
        let k = 0
        while k < trn {
            let tr = machineTransGet(m.transitions, k)
            if machineStateIndex(m, tr.toState) < 0 {
                diag_error(0, "machine " + m.name + ": transition '" + tr.name + "' targets unknown state '" + tr.toState + "'")
            }
            let fcsv = tr.froms
            let start = 0
            let i = 0
            let n = string_len(fcsv)
            while i <= n {
                let isSep = i == n
                if not isSep { if string_char_at(fcsv, i) == 44 { isSep = true } }
                if isSep {
                    let nm = string_slice(fcsv, start, i)
                    if string_len(nm) > 0 and machineStateIndex(m, nm) < 0 {
                        diag_error(0, "machine " + m.name + ": transition '" + tr.name + "' from unknown state '" + nm + "'")
                    }
                    start = i + 1
                }
                i = i + 1
            }
            k = k + 1
        }
        // reachability from the initial state (fixpoint over transitions)
        let reached: String[] = []
        reached = appendString(reached, m.initial)
        let changed = true
        while changed {
            changed = false
            let t = 0
            while t < trn {
                let tr = machineTransGet(m.transitions, t)
                if not strArrContains(reached, tr.toState) {
                    let fcsv = tr.froms
                    let start = 0
                    let i = 0
                    let n = string_len(fcsv)
                    let anyReached = false
                    while i <= n {
                        let isSep = i == n
                        if not isSep { if string_char_at(fcsv, i) == 44 { isSep = true } }
                        if isSep {
                            let nm = string_slice(fcsv, start, i)
                            if string_len(nm) > 0 and strArrContains(reached, nm) { anyReached = true }
                            start = i + 1
                        }
                        i = i + 1
                    }
                    if anyReached { reached = appendString(reached, tr.toState)  changed = true }
                }
                t = t + 1
            }
        }
        // warnings
        let si = 0
        let ns = stringArrLen(m.states)
        while si < ns {
            let st = stringArrGet(m.states, si)
            if not strArrContains(reached, st) {
                diag_warn(0, "machine " + m.name + ": state '" + st + "' is unreachable from '" + m.initial + "'")
            }
            if not strArrContains(m.terminals, st) {
                let hasOut = false
                let t2 = 0
                while t2 < trn {
                    if csvHasState(machineTransGet(m.transitions, t2).froms, st) { hasOut = true }
                    t2 = t2 + 1
                }
                if not hasOut {
                    diag_warn(0, "machine " + m.name + ": non-terminal state '" + st + "' has no outgoing transition (dead end)")
                }
            }
            si = si + 1
        }
        mi = mi + 1
    }
}

// ── Purity enforcement (Phase 2 of the memory-management plan) ──────────────
// A pure-kind function — mapper / predicate / projector — promises no observable
// side effects; that promise is exactly what lets the compiler pass its
// arguments by borrow (they cannot escape). We enforce it: a pure-kind body must
// not perform direct I/O (system.stdout/stderr/stdin) nor call an
// unambiguously-impure function (one whose *every* definition is a `consumer` or
// `action`). Notes on what is deliberately allowed:
//   - extern "C" functions are trusted at their declared kind and never count as
//     impure callees (we can't see their bodies; the FFI boundary is the author's
//     contract — e.g. diag_error/run_command).
//   - `producer` and `creator` are not treated as impure: `producer` is the
//     generic `() -> T` kind (often, but not always, pure — e.g. json.parse), and
//     `creator` only allocates a fresh value. Calling them is fine.
//   - an overloaded name with any non-(consumer/action) definition is not
//     flagged — conservative, so we never reject a legitimate pure call.

// Single switch for the diagnostic severity (warn while bootstrapping, error
// once the tree is known clean).
consumer diag_purity(line: Integer, msg: String) { diag_error(line, msg) }

predicate isPureKind(k: String) {
    return k == "mapper" or k == "predicate" or k == "projector"
}

// Names that are impure in *every* user definition (overloads with any other
// kind are excluded, so the rule is sound against false positives).
mapper collectImpureNames(prog: Program) -> String[] {
    let impure: String[] = []   // >=1 consumer/action definition
    let other:  String[] = []   // >=1 definition of any other kind
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let f = funcSpecGet(prog.functions, i)
        if f.kind == "consumer" or f.kind == "action" { impure = appendString(impure, f.name) }
        else { other = appendString(other, f.name) }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let mth = methodSpecGet(cs.methList, mi)
            if mth.kind == "consumer" or mth.kind == "action" { impure = appendString(impure, mth.name) }
            else { other = appendString(other, mth.name) }
            mi = mi + 1
        }
        ci = ci + 1
    }
    let out: String[] = []
    let k = 0
    let m = stringArrLen(impure)
    while k < m {
        let nm = stringArrGet(impure, k)
        if not strArrContains(other, nm) and not strArrContains(out, nm) {
            out = appendString(out, nm)
        }
        k = k + 1
    }
    return out
}

// Scan one pure-kind body's tokens for I/O and impure calls. String literals are
// single tokens, so names that appear only inside generated-code strings (as in
// codegen itself) never match — only real call sites do.
consumer scanPureBody(kind: String, fname: String, toks: Token[], impure: String[]) {
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        let k = gkind(toks, i)
        // direct I/O:  system . (stdout|stderr|stdin)
        if k == 1 and gtext(toks, i) == "system" and i + 2 < n and gkind(toks, i + 1) == 107 {
            let f2 = gtext(toks, i + 2)
            if f2 == "stdout" or f2 == "stderr" or f2 == "stdin" {
                diag_purity(tokenArrGet(toks, i).line,
                    "pure " + kind + " '" + fname + "' must not perform I/O (system." + f2 + "); use a producer/consumer/action")
            }
        }
        // impure call:  IDENT (
        if k == 1 and i + 1 < n and gkind(toks, i + 1) == 100 {
            let callee = gtext(toks, i)
            if callee != fname and strArrContains(impure, callee) {
                diag_purity(tokenArrGet(toks, i).line,
                    "pure " + kind + " '" + fname + "' must not call impure '" + callee + "'; make it a producer/consumer/action")
            }
        }
        i = i + 1
    }
}

consumer checkPurity(prog: Program) {
    let impure = collectImpureNames(prog)
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let f = funcSpecGet(prog.functions, i)
        if isPureKind(f.kind) { scanPureBody(f.kind, f.name, f.bodyTokens, impure) }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let mth = methodSpecGet(cs.methList, mi)
            if isPureKind(mth.kind) { scanPureBody(mth.kind, mth.name, mth.bodyTokens, impure) }
            mi = mi + 1
        }
        ci = ci + 1
    }
}

mapper funcRetXType(prog: Program, name: String) -> String {
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let fs = funcSpecGet(prog.functions, i)
        if fs.name == name {
            // `async` free function: callers receive a Future<T> over the inner T.
            // (A plain `-> Future<T>` already resolves to a Future xtype below.)
            if fs.isAsync {
                return futureXtypeFor(asyncInnerCtype(fs))
            }
            return resolveX(prog, ctypeToXName(fs.retCtype))
        }
        i = i + 1
    }
    return ""
}

// Is `name` a method of class `cls`? Used to resolve unqualified (and recursive)
// calls inside a method body to a self-dispatched `xc_<cls>_<name>_impl` call.
predicate isSelfMethodC(prog: Program, cls: String, name: String) {
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        if cs.name == cls {
            let mi = 0
            let mn = methodSpecLen(cs.methList)
            while mi < mn {
                if methodSpecGet(cs.methList, mi).name == name { return true }
                mi = mi + 1
            }
            return false
        }
        i = i + 1
    }
    return false
}

mapper selfMethodRetXType(prog: Program, cls: String, name: String) -> String {
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        if cs.name == cls {
            let mi = 0
            let mn = methodSpecLen(cs.methList)
            while mi < mn {
                let ms = methodSpecGet(cs.methList, mi)
                if ms.name == name { return resolveX(prog, ctypeToXName(ms.retCtype)) }
                mi = mi + 1
            }
        }
        i = i + 1
    }
    return ""
}

predicate isExternNameC(prog: Program, name: String) {
    let i = 0
    let n = funcSpecLen(prog.externs)
    while i < n {
        if funcSpecGet(prog.externs, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper externRetXType(prog: Program, name: String) -> String {
    let i = 0
    let n = funcSpecLen(prog.externs)
    while i < n {
        let fs = funcSpecGet(prog.externs, i)
        if fs.name == name { return resolveX(prog, ctypeToXName(fs.retCtype)) }
        i = i + 1
    }
    return ""
}

predicate isTypeNameC(prog: Program, name: String) {
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        if typeSpecGet(prog.types, i).name == name { return true }
        i = i + 1
    }
    let j = 0
    let m = classSpecLen(prog.classes)
    while j < m {
        if classSpecGet(prog.classes, j).name == name { return true }
        j = j + 1
    }
    return false
}

// Is `name` a refined type carrying a `where` constraint?
predicate isRefinedConstrained(prog: Program, name: String) {
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == name {
            if not ts.isCompound {
                if ts.hasWhere { return true }
            }
        }
        i = i + 1
    }
    return false
}

// If compound `typeName`'s `field` has a constrained refined type, return the
// name of its check function (e.g. "xc_check_Age"); else "".
mapper fieldCheckFn(prog: Program, typeName: String, field: String) -> String {
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == typeName {
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let fentry = stringArrGet(ts.fields, fi)
                let colon = findChar(fentry, 58)
                if string_slice(fentry, 0, colon) == field {
                    let fctype = string_slice(fentry, colon + 1, string_len(fentry))
                    let xname = ctypeToXName(fctype)
                    if isRefinedConstrained(prog, xname) { return "xc_check_" + xname }
                    return ""
                }
                fi = fi + 1
            }
        }
        i = i + 1
    }
    return ""
}

mapper fieldTypeNameC(prog: Program, typeName: String, field: String) -> String {
    // Result<T> fields: .ok is Bool, .err is String, .value is T.
    if field == "ok"  { return "Bool" }
    if field == "err" { return "String" }
    if startsWith2(typeName, "res_") and field == "value" {
        let elem = string_slice(typeName, 4, string_len(typeName))
        return resolveX(prog, xnameFromArrSuffix(elem))
    }
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == typeName {
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let fentry = stringArrGet(ts.fields, fi)
                let colon = findChar(fentry, 58)
                let fname = string_slice(fentry, 0, colon)
                if fname == field {
                    let fctype = string_slice(fentry, colon + 1, string_len(fentry))
                    return resolveX(prog, ctypeToXName(fctype))
                }
                fi = fi + 1
            }
        }
        i = i + 1
    }
    return ""
}

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
predicate isPairXType(t: String) { return startsWith2(t, "Pair(") }
mapper pairXtype(a: String, b: String) -> String => "Pair(" + a + ")(" + b + ")"

// Closure type encoding: "Fn(" + csv-of-param-xtypes + ")(" + ret-xtype + ")".
// Balanced parens (group 0 = params, group 1 = return) reuse the Pair extractor,
// so nested function/Pair types parse unambiguously; the C type is always xc_fn_t.
predicate isFnXType(t: String) { return startsWith2(t, "Fn(") }
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
predicate isListXType(typ: String) { return startsWith2(typ, "List_") }
mapper listElemCtype(typ: String) -> String {
    return xnameToCtype(xnameFromArrSuffix(string_slice(typ, 5, string_len(typ))))
}
mapper listElemXName(typ: String) -> String {
    return xnameFromArrSuffix(string_slice(typ, 5, string_len(typ)))
}

// ── Set<T> element-type helpers (xtype "Set_<suffix>") ──────────
predicate isSetXType(typ: String) { return startsWith2(typ, "Set_") }
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
predicate isStackXType(typ: String) { return startsWith2(typ, "Stack_") }
mapper stackElemSuffix(typ: String) -> String { return string_slice(typ, 6, string_len(typ)) }
mapper stackElemCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(stackElemSuffix(typ))) }
mapper stackElemXName(typ: String) -> String { return xnameFromArrSuffix(stackElemSuffix(typ)) }

predicate isQueueXType(typ: String) { return startsWith2(typ, "Queue_") }
mapper queueElemSuffix(typ: String) -> String { return string_slice(typ, 6, string_len(typ)) }
mapper queueElemCtype(typ: String) -> String { return xnameToCtype(xnameFromArrSuffix(queueElemSuffix(typ))) }
mapper queueElemXName(typ: String) -> String { return xnameFromArrSuffix(queueElemSuffix(typ)) }

predicate isSortedQueueXType(typ: String) { return startsWith2(typ, "SortedQueue_") }
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
predicate isFutureXType(typ: String) { return startsWith2(typ, "Future_") }
mapper futureInnerSuffix(typ: String) -> String { return string_slice(typ, 7, string_len(typ)) }
mapper futureInnerXName(typ: String) -> String { return xnameFromArrSuffix(futureInnerSuffix(typ)) }
mapper futureInnerCtype(typ: String) -> String { return xnameToCtype(futureInnerXName(typ)) }
// Is a C return type a Future (`xc_Future_<suf>_t`)?
predicate isFutureCtype(ct: String) { return startsWith2(ct, "xc_Future_") }
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
                out = appendString(out, ctypeToXName(string_slice(ct, 0, string_len(ct) - 1)))
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
        if gkind(toks, i) == 1 and gtext(toks, i) == name {
            if i == a or gkind(toks, i - 1) != 107 { return true }   // 107 = '.'
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
    if gkind(toks, pos) != 1 { return false }
    if gtext(toks, pos) != "runWithDelay" { return false }
    return gkind(toks, pos + 1) == 100
}
mapper parseDelayAt(toks: Token[], pos: Integer) -> DelayParse {
    let msStart = pos + 2                       // past `runWithDelay` `(`
    // find the matching `)` of the ms argument
    let depth = 1
    let p = msStart
    while p < tokenArrLen(toks) and depth > 0 {
        let kk = gkind(toks, p)
        if kk == 100 { depth = depth + 1 }
        if kk == 101 { depth = depth - 1 }
        if depth > 0 { p = p + 1 }
    }
    let msEnd = p                                // the `)`
    let bo = p + 1                               // the body `{`
    let close = matchBrace(toks, bo)
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
            let bctx = withTag(withRet(mkGCtx(prog), "void"), id)
            c = 0
            while c < nc {
                let nm = stringArrGet(caps.names, c)
                let xt = stringArrGet(caps.xtypes, c)
                out = out + "    " + xnameToCtype(xt) + " " + nm + " = __e->" + nm + ";\n"
                bctx = addSym(bctx, nm, xt)
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
predicate isMapXType(typ: String) { return startsWith2(typ, "Map_") }
mapper mapKeySuffix(typ: String) -> String {
    let rest = string_slice(typ, 4, string_len(typ))   // "<ksuf>_<vsuf>"
    if startsWith2(rest, "integer_") { return "integer" }
    if startsWith2(rest, "number_")  { return "number" }
    if startsWith2(rest, "bool_")    { return "bool" }
    if startsWith2(rest, "string_")  { return "string" }
    if startsWith2(rest, "char_")    { return "char" }
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

predicate endsWith2(s: String, suffix: String) {
    let sl = string_len(suffix)
    let n = string_len(s)
    if n < sl { return false }
    return string_slice(s, n - sl, n) == suffix
}

predicate startsWith2(s: String, prefix: String) {
    let pl = string_len(prefix)
    if string_len(s) < pl { return false }
    return string_slice(s, 0, pl) == prefix
}

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
    let k = gkind(toks, start)
    let base = ""
    let p = start
    let pc = primCtypeK(k)
    if string_len(pc) > 0 {
        base = pc
        p = start + 1
    } else {
        if k == 1 {
            base = "xc_" + gtext(toks, start) + "_t"
            p = start + 1
        } else {
            return "void*"
        }
    }
    let suf = ctypeSuffix(base)
    let result = base
    let cont = true
    while cont {
        let pk = gkind(toks, p)
        if pk == 127 {
            result = "xc_opt_" + suf + "_t"
            p = p + 1
        } else {
            if pk == 126 {
                result = "xc_res_" + suf + "_t"
                p = p + 1
            } else {
            if pk == 104 and gkind(toks, p + 1) == 105 {
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
    return addSym(ctx, name, resolveX(ctx.prog, ctypeToXName(ctype)))
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

// ── argument list ─────────────────────────────────────────────────
mapper genArgs(toks: Token[], pos: Integer, ctx: GCtx) -> GArgs {
    let p = pos + 1
    let firstRaw = gtext(toks, p)
    let out = ""
    let first = true
    while gkind(toks, p) != 101 and gkind(toks, p) != 0 {
        let e = genExpr(toks, p, ctx)
        p = e.pos
        if not first { out = out + ", " }
        out = out + e.code
        first = false
        if gkind(toks, p) == 106 { p = p + 1 }
    }
    if gkind(toks, p) == 101 { p = p + 1 }
    return GArgs { code: out, pos: p, firstRaw: firstRaw }
}

// ── type literal:  TypeName { field: expr, ... } ──────────────────
mapper genTypeLiteral(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let typeName = gtext(toks, pos)
    let p = pos + 2
    let out = "(xc_" + typeName + "_t){ "
    let first = true
    while gkind(toks, p) != 103 and gkind(toks, p) != 0 {
        let fname = gtext(toks, p)
        p = p + 1
        if gkind(toks, p) == 108 { p = p + 1 }
        let e = genExpr(toks, p, ctx)
        p = e.pos
        if not first { out = out + ", " }
        // Construction is gated: if the field's type is a refined type, run its
        // constraint check on the assigned value.
        let chk = fieldCheckFn(ctx.prog, typeName, fname)
        let val = e.code
        if string_len(chk) > 0 { val = chk + "(" + e.code + ")" }
        out = out + "." + fname + " = " + val
        first = false
        if gkind(toks, p) == 106 { p = p + 1 }
    }
    if gkind(toks, p) == 103 { p = p + 1 }
    out = out + " }"
    return ExprRes { code: out, pos: p, xtyp: typeName , owned: false }
}

// Construct a sum-type value:  Variant { f: v, ... }  or a bare  Variant.
mapper genVariantLiteral(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let vname = gtext(toks, pos)
    let sum = sumOfVariant(ctx.prog, vname)
    if gkind(toks, pos + 1) != 102 {                      // no payload
        return ExprRes {
            code: "(xc_" + sum + "_t){ .tag = xc_" + sum + "_" + vname + " }",
            pos: pos + 1, xtyp: sum
        , owned: false }
    }
    let p = pos + 2
    let inner = ""
    let first = true
    while gkind(toks, p) != 103 and gkind(toks, p) != 0 {
        let fname = gtext(toks, p)
        p = p + 1
        if gkind(toks, p) == 108 { p = p + 1 }           // :
        let e = genExpr(toks, p, ctx)
        p = e.pos
        if not first { inner = inner + ", " }
        inner = inner + "." + fname + " = " + e.code
        first = false
        if gkind(toks, p) == 106 { p = p + 1 }           // ,
    }
    if gkind(toks, p) == 103 { p = p + 1 }               // }
    return ExprRes {
        code: "(xc_" + sum + "_t){ .tag = xc_" + sum + "_" + vname + ", .u." + vname + " = { " + inner + " } }",
        pos: p, xtyp: sum
    , owned: false }
}

// ── first-class closures: lambdas `(p: T, …) => expr` ─────────────────────────
// A lambda lowers to a top-level `static R xc_lam_<tag>_<pos>(void* env, params…)`
// (emitted by hoistLambdas, keyed by token position so the value site names the
// same helper) and an xc_fn_t value { fn, env }. v1: capture-free (the body sees
// only the params) with single-token param types; call via the Fn(...) xtype.
type LamParams = { cparams: String, pctypes: String, bodyStart: Integer, ctx: GCtx }

// `pos` at the lambda's '(' — is it `( … ) =>` (a lambda) rather than a grouped
// expression?
predicate isLambdaAt(toks: Token[], pos: Integer) {
    if gkind(toks, pos) != 100 { return false }
    let n = tokenArrLen(toks)
    let rp = pos + 1
    let pd = 1
    while rp < n and pd > 0 {
        let kk = gkind(toks, rp)
        if kk == 100 { pd = pd + 1 }
        if kk == 101 { pd = pd - 1 }
        if pd > 0 { rp = rp + 1 }
    }
    return gkind(toks, rp + 1) == 110   // '=>' after the matching ')'
}

mapper parseLamParams(toks: Token[], pos: Integer, prog: Program) -> LamParams {
    let p = pos + 1                        // past '('
    let cparams = ""
    let pctypes = ""
    let pctx = mkGCtx(prog)
    let first = true
    while gkind(toks, p) != 101 and gkind(toks, p) != 0 {
        if gkind(toks, p) == 106 { p = p + 1 }    // ,
        let nm = gtext(toks, p)
        p = p + 1
        if gkind(toks, p) == 108 { p = p + 1 }    // :
        let pc = typeCtypeOf(toks, p)
        p = p + 1                                  // single-token param type
        if not first { cparams = cparams + ", "  pctypes = pctypes + "," }
        cparams = cparams + pc + " " + nm
        pctypes = pctypes + pc
        pctx = addSym(pctx, nm, ctypeToXName(pc))
        first = false
    }
    let bs = p
    if gkind(toks, bs) == 101 { bs = bs + 1 }      // ')'
    if gkind(toks, bs) == 110 { bs = bs + 1 }      // '=>'
    return LamParams { cparams: cparams, pctypes: pctypes, bodyStart: bs, ctx: pctx }
}

mapper genLambda(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let lp = parseLamParams(toks, pos, ctx.prog)
    let body = genExpr(toks, lp.bodyStart, lp.ctx)
    let retC = xnameToCtype(body.xtyp)
    let id = "xc_lam_" + ctx.fnTag + "_" + int_to_string(pos)
    let fnX = "Fn(" + lp.pctypes + ")(" + retC + ")"
    return ExprRes { code: "(xc_fn_t){ (void*)" + id + ", (void*)0 }", pos: body.pos, xtyp: fnX , owned: false }
}

// Emit a top-level C function for every lambda in `toks` (mirrors hoistParallel).
mapper hoistLambdas(prog: Program, toks: Token[], tag: String) -> String {
    let out = ""
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        if isLambdaAt(toks, i) {
            let lp = parseLamParams(toks, i, prog)
            let body = genExpr(toks, lp.bodyStart, lp.ctx)
            let retC = xnameToCtype(body.xtyp)
            let id = "xc_lam_" + tag + "_" + int_to_string(i)
            let sig = "void* __env"
            if string_len(lp.cparams) > 0 { sig = sig + ", " + lp.cparams }
            out = out + "static " + retC + " " + id + "(" + sig + ") {\n"
                      + "    (void)__env;\n    return (" + body.code + ");\n}\n"
        }
        i = i + 1
    }
    return out
}

// ── primary ───────────────────────────────────────────────────────
mapper genPrimary(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let k = gkind(toks, pos)
    let txt = gtext(toks, pos)
    // `empty T` — the zero value of T (struct all-zero, array empty, ...).
    // Contextual: only when `empty` starts a primary AND is followed by a type
    // (so `bytes.empty()` and any var/field named `empty` still work).
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "List" and gkind(toks, pos + 2) == 114 {
        // `empty List<T>` — a fresh, empty list
        let etk = gkind(toks, pos + 3)
        let elemCtype = primCtypeK(etk)
        if string_len(elemCtype) == 0 { elemCtype = "xc_" + gtext(toks, pos + 3) + "_t" }
        let endp = pos + 4
        if gkind(toks, endp) == 115 { endp = endp + 1 }   // `>`
        return ExprRes {
            code: "xstd_list_new(sizeof(" + elemCtype + "))",
            pos: endp, xtyp: "List_" + ctypeSuffix(elemCtype)
        , owned: false }
    }
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "Set" and gkind(toks, pos + 2) == 114 {
        // `empty Set<T>` — a fresh, empty set
        let etk = gkind(toks, pos + 3)
        let elemCtype = primCtypeK(etk)
        if string_len(elemCtype) == 0 { elemCtype = "xc_" + gtext(toks, pos + 3) + "_t" }
        let endp = pos + 4
        if gkind(toks, endp) == 115 { endp = endp + 1 }   // `>`
        return ExprRes {
            code: "xstd_set_new(sizeof(" + elemCtype + "), " + strFlagFor(elemCtype) + ")",
            pos: endp, xtyp: "Set_" + ctypeSuffix(elemCtype)
        , owned: false }
    }
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "Map" and gkind(toks, pos + 2) == 114 {
        // `empty Map<K, V>` — a fresh, empty map (K is a primitive or String)
        let ktk = gkind(toks, pos + 3)
        let kc = primCtypeK(ktk)
        if string_len(kc) == 0 { kc = "xc_" + gtext(toks, pos + 3) + "_t" }
        let q = pos + 4
        if gkind(toks, q) == 106 { q = q + 1 }            // `,`
        let vtk = gkind(toks, q)
        let vc = primCtypeK(vtk)
        if string_len(vc) == 0 { vc = "xc_" + gtext(toks, q) + "_t" }
        let endp = q + 1
        if gkind(toks, endp) == 115 { endp = endp + 1 }   // `>`
        return ExprRes {
            code: "xstd_map_new(sizeof(" + kc + "), sizeof(" + vc + "), " + strFlagFor(kc) + ")",
            pos: endp, xtyp: "Map_" + ctypeSuffix(kc) + "_" + ctypeSuffix(vc)
        , owned: false }
    }
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "Vec" and gkind(toks, pos + 2) == 114 {
        // `empty Vec<T>` — a fresh, empty vector (a List under the hood)
        let etk = gkind(toks, pos + 3)
        let elemCtype = primCtypeK(etk)
        if string_len(elemCtype) == 0 { elemCtype = "xc_" + gtext(toks, pos + 3) + "_t" }
        let endp = pos + 4
        if gkind(toks, endp) == 115 { endp = endp + 1 }   // `>`
        return ExprRes {
            code: "xstd_list_new(sizeof(" + elemCtype + "))",
            pos: endp, xtyp: "List_" + ctypeSuffix(elemCtype)
        , owned: false }
    }
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "Stack" and gkind(toks, pos + 2) == 114 {
        let etk = gkind(toks, pos + 3)
        let elemCtype = primCtypeK(etk)
        if string_len(elemCtype) == 0 { elemCtype = "xc_" + gtext(toks, pos + 3) + "_t" }
        let endp = pos + 4
        if gkind(toks, endp) == 115 { endp = endp + 1 }
        return ExprRes {
            code: "xstd_stack_new(sizeof(" + elemCtype + "))",
            pos: endp, xtyp: "Stack_" + ctypeSuffix(elemCtype)
        , owned: false }
    }
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "Queue" and gkind(toks, pos + 2) == 114 {
        let etk = gkind(toks, pos + 3)
        let elemCtype = primCtypeK(etk)
        if string_len(elemCtype) == 0 { elemCtype = "xc_" + gtext(toks, pos + 3) + "_t" }
        let endp = pos + 4
        if gkind(toks, endp) == 115 { endp = endp + 1 }
        return ExprRes {
            code: "xstd_queue_new(sizeof(" + elemCtype + "))",
            pos: endp, xtyp: "Queue_" + ctypeSuffix(elemCtype)
        , owned: false }
    }
    if k == 1 and txt == "empty" and gtext(toks, pos + 1) == "SortedQueue" and gkind(toks, pos + 2) == 114 {
        let etk = gkind(toks, pos + 3)
        let elemCtype = primCtypeK(etk)
        if string_len(elemCtype) == 0 { elemCtype = "xc_" + gtext(toks, pos + 3) + "_t" }
        let endp = pos + 4
        if gkind(toks, endp) == 115 { endp = endp + 1 }
        return ExprRes {
            code: "xstd_pqueue_new(sizeof(" + elemCtype + "), " + pqCmpKind(elemCtype) + ")",
            pos: endp, xtyp: "SortedQueue_" + ctypeSuffix(elemCtype)
        , owned: false }
    }
    // ── builders: listOf(a, b, ...) / setOf(a, b, ...) / mapOf(k to v, ...) ──
    // Element/key types are inferred from the first argument (homogeneous).
    // readConfig<T>("file.{json,yaml,xml}") — read + decode a config file into T
    if k == 1 and txt == "readConfig" and gkind(toks, pos + 1) == 114 {
        let tname = gtext(toks, pos + 2)         // T
        let q = pos + 3
        if gkind(toks, q) == 115 { q = q + 1 }   // >
        if gkind(toks, q) == 100 { q = q + 1 }   // (
        let pe = genExpr(toks, q, ctx)           // the path expression
        q = pe.pos
        if gkind(toks, q) == 101 { q = q + 1 }   // )
        return ExprRes {
            code: "xc_fromjson_" + tname + "(xstd_config_parse(" + pe.code + "))",
            pos: q, xtyp: tname
        , owned: false }
    }
    if k == 1 and txt == "generateSequence" and gkind(toks, pos + 1) == 100 {
        // generateSequence(seed) { [p =>] next } .<lazy ops> .<terminal> — a fused
        // lazy recurrence source: the value starts at `seed` and advances through
        // the inlined generator each step. Must be bounded by a take/takeWhile/
        // first in the chain, or it loops forever.
        let se = genExpr(toks, pos + 2, ctx)
        let seedX = se.xtyp
        let aq = se.pos
        if gkind(toks, aq) == 101 { aq = aq + 1 }                 // ')'
        let bo = aq                                               // '{'
        let close = matchBrace(toks, bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let gp = "it"
        let bstart = bo + 1
        if arrow >= 0 { gp = gtext(toks, bo + 1)  bstart = arrow + 1 }
        let gbody = genExpr(toks, bstart, addSym(ctx, gp, seedX))
        let dotp = close + 1                                      // first '.' of the chain
        return genSequenceChain(toks, dotp - 2, "", seedX, ctx, true, se.code, gbody.code, gp)
    }
    if k == 1 and txt == "listOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let first = genExpr(toks, pos + 2, ctx)
        let ec = xnameToCtype(first.xtyp)
        let body = "xc_List_t _t = xstd_list_new(sizeof(" + ec + ")); "
                 + "xstd_list_push(_t, (" + ec + "[]){ " + first.code + " }); "
        let p = first.pos
        while gkind(toks, p) == 106 {
            let a = genExpr(toks, p + 1, ctx)
            body = body + "xstd_list_push(_t, (" + ec + "[]){ " + a.code + " }); "
            p = a.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_t; })", pos: p, xtyp: "List_" + arrSuffixOf(first.xtyp) , owned: false }
    }
    if k == 1 and txt == "vecOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let first = genExpr(toks, pos + 2, ctx)
        let ec = xnameToCtype(first.xtyp)
        let body = "xc_List_t _t = xstd_list_new(sizeof(" + ec + ")); "
                 + "xstd_list_push(_t, (" + ec + "[]){ " + first.code + " }); "
        let p = first.pos
        while gkind(toks, p) == 106 {
            let a = genExpr(toks, p + 1, ctx)
            body = body + "xstd_list_push(_t, (" + ec + "[]){ " + a.code + " }); "
            p = a.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_t; })", pos: p, xtyp: "List_" + arrSuffixOf(first.xtyp) , owned: false }
    }
    if k == 1 and txt == "stackOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let first = genExpr(toks, pos + 2, ctx)
        let ec = xnameToCtype(first.xtyp)
        let body = "xc_Stack_t _t = xstd_stack_new(sizeof(" + ec + ")); "
                 + "xstd_stack_push(_t, (" + ec + "[]){ " + first.code + " }); "
        let p = first.pos
        while gkind(toks, p) == 106 {
            let a = genExpr(toks, p + 1, ctx)
            body = body + "xstd_stack_push(_t, (" + ec + "[]){ " + a.code + " }); "
            p = a.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_t; })", pos: p, xtyp: "Stack_" + arrSuffixOf(first.xtyp) , owned: false }
    }
    if k == 1 and txt == "queueOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let first = genExpr(toks, pos + 2, ctx)
        let ec = xnameToCtype(first.xtyp)
        let body = "xc_Queue_t _t = xstd_queue_new(sizeof(" + ec + ")); "
                 + "xstd_queue_enqueue(_t, (" + ec + "[]){ " + first.code + " }); "
        let p = first.pos
        while gkind(toks, p) == 106 {
            let a = genExpr(toks, p + 1, ctx)
            body = body + "xstd_queue_enqueue(_t, (" + ec + "[]){ " + a.code + " }); "
            p = a.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_t; })", pos: p, xtyp: "Queue_" + arrSuffixOf(first.xtyp) , owned: false }
    }
    if k == 1 and txt == "sortedQueueOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let first = genExpr(toks, pos + 2, ctx)
        let ec = xnameToCtype(first.xtyp)
        let body = "xc_SortedQueue_t _t = xstd_pqueue_new(sizeof(" + ec + "), " + pqCmpKind(ec) + "); "
                 + "xstd_pqueue_push(_t, (" + ec + "[]){ " + first.code + " }); "
        let p = first.pos
        while gkind(toks, p) == 106 {
            let a = genExpr(toks, p + 1, ctx)
            body = body + "xstd_pqueue_push(_t, (" + ec + "[]){ " + a.code + " }); "
            p = a.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_t; })", pos: p, xtyp: "SortedQueue_" + arrSuffixOf(first.xtyp) , owned: false }
    }
    if k == 1 and txt == "setOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let first = genExpr(toks, pos + 2, ctx)
        let ec = xnameToCtype(first.xtyp)
        let body = "xc_Set_t _s = xstd_set_new(sizeof(" + ec + "), " + strFlagFor(ec) + "); "
                 + "xstd_set_add(_s, (" + ec + "[]){ " + first.code + " }); "
        let p = first.pos
        while gkind(toks, p) == 106 {
            let a = genExpr(toks, p + 1, ctx)
            body = body + "xstd_set_add(_s, (" + ec + "[]){ " + a.code + " }); "
            p = a.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_s; })", pos: p, xtyp: "Set_" + arrSuffixOf(first.xtyp) , owned: false }
    }
    if k == 1 and txt == "mapOf" and gkind(toks, pos + 1) == 100 and gkind(toks, pos + 2) != 101 {
        let k1 = genAnd(toks, pos + 2, ctx)   // genAnd, not genExpr, so the `to` stays for us
        let kc = xnameToCtype(k1.xtyp)
        let q = k1.pos
        if gkind(toks, q) == 1 and gtext(toks, q) == "to" { q = q + 1 }   // `k to v`
        let v1 = genExpr(toks, q, ctx)
        let vc = xnameToCtype(v1.xtyp)
        let body = "xc_Map_t _m = xstd_map_new(sizeof(" + kc + "), sizeof(" + vc + "), " + strFlagFor(kc) + "); "
                 + "xstd_map_put(_m, (" + kc + "[]){ " + k1.code + " }, (" + vc + "[]){ " + v1.code + " }); "
        let p = v1.pos
        while gkind(toks, p) == 106 {
            let kk = genAnd(toks, p + 1, ctx)   // genAnd so `to` stays for us
            let qq = kk.pos
            if gkind(toks, qq) == 1 and gtext(toks, qq) == "to" { qq = qq + 1 }
            let vv = genExpr(toks, qq, ctx)
            body = body + "xstd_map_put(_m, (" + kc + "[]){ " + kk.code + " }, (" + vc + "[]){ " + vv.code + " }); "
            p = vv.pos
        }
        if gkind(toks, p) == 101 { p = p + 1 }
        return ExprRes { code: "({ " + body + "_m; })", pos: p, xtyp: "Map_" + arrSuffixOf(k1.xtyp) + "_" + arrSuffixOf(v1.xtyp) , owned: false }
    }
    if k == 1 and txt == "empty" {
        let nk = gkind(toks, pos + 1)
        if nk == 1 or string_len(primCtypeK(nk)) > 0 {
            let ctype = typeCtypeOf(toks, pos + 1)
            let tp = pos + 2                     // after the base type token
            let cont = true
            while cont {
                let pk = gkind(toks, tp)
                if pk == 127 { tp = tp + 1 }                                   // ?
                else { if pk == 126 { tp = tp + 1 }                            // !
                else { if pk == 104 and gkind(toks, tp + 1) == 105 { tp = tp + 2 }  // []
                else { cont = false } } }
            }
            return ExprRes { code: "(" + ctype + "){0}", pos: tp, xtyp: gtext(toks, pos + 1) , owned: false }
        }
    }
    if k == 2 { return ExprRes { code: txt + "LL", pos: pos + 1, xtyp: "Integer" , owned: false } }
    if k == 3 { return ExprRes { code: txt, pos: pos + 1, xtyp: "Number" , owned: false } }
    if k == 4 { return ExprRes { code: "xc_string_from_cstr(\"" + txt + "\")", pos: pos + 1, xtyp: "String" , owned: false } }
    if k == 236 { return ExprRes { code: "true", pos: pos + 1, xtyp: "Bool" , owned: false } }
    if k == 237 { return ExprRes { code: "false", pos: pos + 1, xtyp: "Bool" , owned: false } }
    if k == 254 { return ExprRes { code: "{0}", pos: pos + 1, xtyp: "" , owned: false } }
    if k == 253 { return ExprRes { code: "input", pos: pos + 1, xtyp: "" , owned: false } }
    if k == 243 { return ExprRes { code: "value", pos: pos + 1, xtyp: lookupVar(ctx, "value") , owned: false } }
    if k == 238 { return ExprRes { code: "self", pos: pos + 1, xtyp: "self" , owned: false } }
    if k == 100 {
        if isLambdaAt(toks, pos) { return genLambda(toks, pos, ctx) }
        let inner = genExpr(toks, pos + 1, ctx)
        let p2 = inner.pos
        if gkind(toks, p2) == 101 { p2 = p2 + 1 }
        return ExprRes { code: "(" + inner.code + ")", pos: p2, xtyp: inner.xtyp , owned: false }
    }
    if k == 104 {
        // Array literal [ e1, e2, ... ]
        let p = pos + 1
        let out = ""
        let count = 0
        let firstX = ""
        let first = true
        while gkind(toks, p) != 105 and gkind(toks, p) != 0 {
            let e = genExpr(toks, p, ctx)
            p = e.pos
            if first { firstX = e.xtyp }
            if not first { out = out + ", " }
            out = out + e.code
            count = count + 1
            first = false
            if gkind(toks, p) == 106 { p = p + 1 }
        }
        if gkind(toks, p) == 105 { p = p + 1 }
        if count == 0 {
            return ExprRes { code: "{0}", pos: p, xtyp: "emptyarr" , owned: false }
        }
        let arrType = "xc_arr_" + arrSuffixOf(firstX) + "_t"
        let elemCtype = xnameToCtype(firstX)
        let code = "(" + arrType + "){ .data = (" + elemCtype + "[]){ " + out
                 + " }, .len = " + int_to_string(count) + ", .cap = " + int_to_string(count) + " }"
        return ExprRes { code: code, pos: p, xtyp: arrSuffixOf(firstX) + "[]" , owned: false }
    }
    if k == 1 {
        if isParallelAt(toks, pos) {
            // parallel [(cap,...)] { body } -> spawn a thread, yield a Thread
            let pp = parseParallelAt(toks, pos)
            let id = ctx.fnTag + "_" + int_to_string(pos)
            let args = ""
            let nc = stringArrLen(pp.caps)
            let c = 0
            while c < nc {
                if c > 0 { args = args + ", " }
                args = args + stringArrGet(pp.caps, c)
                c = c + 1
            }
            return ExprRes { code: "xc_parspawn_" + id + "(" + args + ")", pos: pp.endPos, xtyp: "Thread" , owned: false }
        }
        if isRunWithDelayAt(toks, pos) {
            // runWithDelay(ms) { body } -> run body after `ms`, yield Future<Integer>
            let dp = parseDelayAt(toks, pos)
            let id = ctx.fnTag + "_" + int_to_string(pos)
            let ms = genExpr(toks, dp.msStart, ctx)
            let caps = capturesIn(toks, dp.bodyStart, dp.bodyEnd, ctx.capNames, ctx.capTypes)
            let args = ms.code
            let nc = stringArrLen(caps.names)
            let c = 0
            while c < nc { args = args + ", " + stringArrGet(caps.names, c)  c = c + 1 }
            return ExprRes { code: "xc_delayspawn_" + id + "(" + args + ")", pos: dp.endPos, xtyp: "Future_integer" , owned: false }
        }
        if txt == "thread" {
            // built-in thread facility: thread.channel() / thread.stopped()
            return ExprRes { code: "", pos: pos + 1, xtyp: "thread:" , owned: false }
        }
        if isVariantNameC(ctx.prog, txt) {
            // sum-type constructor: Variant { ... } or a bare nullary Variant
            return genVariantLiteral(toks, pos, ctx)
        }
        if gkind(toks, pos + 1) == 102 and isTypeNameC(ctx.prog, txt) {
            return genTypeLiteral(toks, pos, ctx)
        }
        if isDepNameC(ctx, txt) {
            return ExprRes { code: "self->" + txt, pos: pos + 1, xtyp: depTypeOf(ctx, txt) , owned: false }
        }
        if txt == "system" {
            return ExprRes { code: "system", pos: pos + 1, xtyp: "ns:system" , owned: false }
        }
        if txt == "Events" {
            // built-in event facility: Events.dispatch/encode/decode/topic/type/run
            return ExprRes { code: "", pos: pos + 1, xtyp: "events:" , owned: false }
        }
        if isModuleNameC(ctx.prog, txt) {
            return ExprRes { code: txt, pos: pos + 1, xtyp: "module:" + txt , owned: false }
        }
        if isAtomNameC(ctx.prog, txt) {
            return ExprRes { code: "__atom_" + txt, pos: pos + 1, xtyp: "atom:" + txt , owned: false }
        }
        if isMachineTypeC(ctx.prog, txt) {
            return ExprRes { code: txt, pos: pos + 1, xtyp: "machinetype:" + txt , owned: false }
        }
        return ExprRes { code: txt, pos: pos + 1, xtyp: lookupVar(ctx, txt) , owned: false }
    }
    return ExprRes { code: txt, pos: pos + 1, xtyp: "" , owned: false }
}

// ── functional API on List<T> (lambdas inlined as generated loops) ─────────
// Method names that take a `{ lambda }` (and maybe a leading `(arg)`).
predicate isListFunc(fld: String) {
    if fld == "map"      { return true }
    if fld == "filter"   { return true }
    if fld == "filterNot"{ return true }
    if fld == "partition"{ return true }
    if fld == "zip"      { return true }
    if fld == "unzip"    { return true }
    if fld == "forEach"  { return true }
    if fld == "fold"     { return true }
    if fld == "reduce"   { return true }
    if fld == "count"    { return true }
    if fld == "any"      { return true }
    if fld == "all"      { return true }
    if fld == "none"     { return true }
    if fld == "sumOf"    { return true }
    if fld == "joinToString" { return true }
    if fld == "mapIndexed" { return true }
    if fld == "takeWhile" { return true }
    if fld == "dropWhile" { return true }
    if fld == "flatMap"  { return true }
    if fld == "take"     { return true }
    if fld == "drop"     { return true }
    if fld == "reversed" { return true }
    if fld == "distinct" { return true }
    if fld == "first"    { return true }
    if fld == "last"     { return true }
    if fld == "toSet"    { return true }
    if fld == "find"     { return true }
    if fld == "firstOrNone" { return true }
    if fld == "lastOrNone"  { return true }
    if fld == "maxByOrNone" { return true }
    if fld == "minByOrNone" { return true }
    if fld == "average"  { return true }
    if fld == "sorted"   { return true }
    if fld == "sortedDescending" { return true }
    if fld == "sortedBy" { return true }
    if fld == "sortedByDescending" { return true }
    if fld == "groupBy"  { return true }
    if fld == "associateBy" { return true }
    if fld == "associateWith" { return true }
    if fld == "chunked"  { return true }
    if fld == "windowed" { return true }
    if fld == "sum"      { return true }
    if fld == "min"      { return true }
    if fld == "max"      { return true }
    if fld == "minOrNone" { return true }
    if fld == "maxOrNone" { return true }
    if fld == "contains" { return true }
    if fld == "indexOf"  { return true }
    if fld == "toList"   { return true }
    if fld == "withIndex" { return true }
    if fld == "flatten"  { return true }
    if fld == "single"   { return true }
    if fld == "singleOrNone" { return true }
    if fld == "onEach"   { return true }
    if fld == "maxOf"    { return true }
    if fld == "minOf"    { return true }
    if fld == "scan"     { return true }
    if fld == "runningFold" { return true }
    return false
}
// index of the top-level `=>` (kind 110) within (start, close), or -1.
mapper lambdaArrow(toks: Token[], start: Integer, close: Integer) -> Integer {
    let depth = 0
    let i = start
    while i < close {
        let k = gkind(toks, i)
        if k == 102 or k == 100 or k == 104 { depth = depth + 1 }
        if k == 103 or k == 101 or k == 105 { depth = depth - 1 }
        if depth == 0 and k == 110 { return i }
        i = i + 1
    }
    return 0 - 1
}

// Lazy sequences: `list.asSequence().<lazy ops>.<terminal>` fuses the whole
// chain into ONE loop (no intermediate lists). `p` is at the `.` of asSequence;
// `src` is the source list code, `elemX0` its element xtype.
mapper genSequenceChain(toks: Token[], p: Integer, src: String, elemX0: String, ctx: GCtx, genMode: Bool, seedC: String, genBodyC: String, genParam: String) -> ExprRes {
    let u = int_to_string(p)
    let sv = "_sq" + u
    let iv = "_qi" + u
    let gv = "_gv" + u
    let q = p + 2
    if gkind(toks, q) == 100 { q = q + 1  if gkind(toks, q) == 101 { q = q + 1 } }   // ()
    let curVar = "_e" + u + "_0"
    let curX = elemX0
    let curC = xnameToCtype(curX)
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
    while going and gkind(toks, q) == 107 {
        let fld = gtext(toks, q + 1)
        if fld == "map" or fld == "filter" or fld == "filterNot" or fld == "takeWhile" or fld == "dropWhile" {
            let bo = q + 2
            let close = matchBrace(toks, bo)
            let arrow = lambdaArrow(toks, bo + 1, close)
            let param = "it"
            let bstart = bo + 1
            if arrow >= 0 { param = gtext(toks, bo + 1)  bstart = arrow + 1 }
            let body = genExpr(toks, bstart, addSym(ctx, param, curX))
            // each op binds its param in its own block so reused names (e.g. `it`) don't clash
            if fld == "map" {
                step = step + 1
                let nv = "_e" + u + "_" + int_to_string(step)
                let nc = xnameToCtype(body.xtyp)
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
            if gkind(toks, q) == 101 { q = q + 1 }
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
    let tf = gtext(toks, q + 1)
    if tf == "toList" or tf == "toSet" {
        let add = "xstd_list_push"
        let tx = "List_" + arrSuffixOf(curX)
        let newc = "xstd_list_new(sizeof(" + curC + "))"
        if tf == "toSet" { add = "xstd_set_add"  tx = "Set_" + arrSuffixOf(curX)  newc = "xstd_set_new(sizeof(" + curC + "), " + strFlagFor(curC) + ")" }
        let code = head + "      __auto_type _out" + u + " = " + newc + ";\n" + loopHdr + inner
                 + "        " + add + "(_out" + u + ", &" + curVar + "); } _out" + u + "; })"
        return ExprRes { code: code, pos: q + 4, xtyp: tx , owned: false }
    }
    if tf == "forEach" {
        let bo = q + 2  let close = matchBrace(toks, bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let param = "it"  let bstart = bo + 1
        if arrow >= 0 { param = gtext(toks, bo + 1)  bstart = arrow + 1 }
        let body = genExpr(toks, bstart, addSym(ctx, param, curX))
        let code = head + loopHdr + inner + "        " + curC + " " + param + " = " + curVar + "; (void)(" + body.code + "); } (void)0; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "" , owned: false }
    }
    if tf == "fold" {
        let ae = genExpr(toks, q + 3, ctx)  let seed = ae.code  let accX = ae.xtyp
        let qq = ae.pos
        if gkind(toks, qq) == 101 { qq = qq + 1 }
        let bo = qq  let close = matchBrace(toks, bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let pa = "acc"  let px = "x"  let bstart = bo + 1
        if arrow >= 0 {
            let pi = bo + 1  let firstP = true
            while pi < arrow { if gkind(toks, pi) == 1 { if firstP { pa = gtext(toks, pi)  firstP = false } else { px = gtext(toks, pi) } } pi = pi + 1 }
            bstart = arrow + 1
        }
        let body = genExpr(toks, bstart, addSym(addSym(ctx, pa, accX), px, curX))
        let accC = xnameToCtype(accX)
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
        let bo = q + 2  let close = matchBrace(toks, bo)
        let arrow = lambdaArrow(toks, bo + 1, close)
        let param = "it"  let bstart = bo + 1
        if arrow >= 0 { param = gtext(toks, bo + 1)  bstart = arrow + 1 }
        let body = genExpr(toks, bstart, addSym(ctx, param, curX))
        let init = "0"  let setv = "1"  let cond = "(" + body.code + ")"
        if tf == "all" { init = "1"  setv = "0"  cond = "!(" + body.code + ")" }
        let code = head + "      xc_bool_t _r" + u + " = " + init + ";\n" + loopHdr + inner
                 + "        " + curC + " " + param + " = " + curVar + "; if (" + cond + ") { _r" + u + " = " + setv + "; break; } } _r" + u + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Bool" , owned: false }
    }
    if tf == "firstOrNone" {
        let suf = arrSuffixOf(curX)
        let code = head + "      xc_opt_" + suf + "_t _r" + u + "; _r" + u + ".has_value = 0;\n" + loopHdr + inner
                 + "        _r" + u + ".has_value = 1; _r" + u + ".value = " + curVar + "; break; } _r" + u + "; })"
        return ExprRes { code: code, pos: q + 4, xtyp: "opt_" + suf , owned: false }
    }
    // first() — first surviving element (aborts if none)
    let fcode = head + "      xc_opt_" + arrSuffixOf(curX) + "_t _r" + u + "; _r" + u + ".has_value = 0;\n" + loopHdr + inner
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
        + "      " + keyC + "* " + ks + " = (" + keyC + "*)malloc((" + nN + " > 0 ? " + nN + " : 1) * sizeof(" + keyC + "));\n"
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
    let elem = listElemCtype(typ)
    let elemX = listElemXName(typ)
    let u = int_to_string(p)
    let sv = "_s" + u
    let iv = "_i" + u
    let rv = "_r" + u
    let suf = string_slice(typ, 5, string_len(typ))   // element arr-suffix (typ = "List_<suf>")
    let strF = strFlagFor(elem)
    let declSv = "xc_List_t " + sv + " = " + recv + ";\n      "
    let q = p + 2
    // optional leading (arg): take/drop count, fold seed, joinToString separator
    let argCode = ""
    let argX = ""
    if gkind(toks, q) == 100 {
        if gkind(toks, q + 1) == 101 {
            q = q + 2                                  // empty ()
        } else {
            let ae = genExpr(toks, q + 1, ctx)
            argCode = ae.code
            argX = ae.xtyp
            q = ae.pos
            if gkind(toks, q) == 101 { q = q + 1 }
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
        let bX = listElemXName(argX)
        let bC = xnameToCtype(bX)
        let pX = pairXtype(elemX, bX)
        let ys = "_ys" + u
        let nn = "_n" + u
        let code = "({ " + declSv + "xc_List_t " + ys + " = (" + argCode + ");\n"
                 + "      xc_List_t " + rv + " = xstd_list_new(sizeof(xc_pair_t));\n"
                 + "      xc_integer_t " + nn + " = xstd_list_len(" + sv + "); xc_integer_t _m" + u + " = xstd_list_len(" + ys + "); if (_m" + u + " < " + nn + ") " + nn + " = _m" + u + ";\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < " + nn + "; " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_pair_t _pp" + u + " = xc_pair_make(xstd_list_at(" + sv + ", " + iv + "), sizeof(" + elem + "), xstd_list_at(" + ys + ", " + iv + "), sizeof(" + bC + "));\n"
                 + "        xstd_list_push(" + rv + ", &_pp" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_" + arrSuffixOf(pX) , owned: false }
    }
    if fld == "unzip" {
        // unzip: List<Pair<A,B>> -> Pair<List<A>, List<B>>.
        let aX = pairElem(elemX, 0)
        let bX = pairElem(elemX, 1)
        let aC = xnameToCtype(aX)
        let bC = xnameToCtype(bX)
        let la = "_la" + u
        let lb = "_lb" + u
        let code = "({ " + declSv + "xc_List_t " + la + " = xstd_list_new(sizeof(" + aC + ")); xc_List_t " + lb + " = xstd_list_new(sizeof(" + bC + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_pair_t* _pp" + u + " = (xc_pair_t*)xstd_list_at(" + sv + ", " + iv + "); xstd_list_push(" + la + ", _pp" + u + "->first); xstd_list_push(" + lb + ", _pp" + u + "->second); }\n"
                 + "      xc_pair_make(&" + la + ", sizeof(xc_List_t), &" + lb + ", sizeof(xc_List_t)); })"
        return ExprRes { code: code, pos: q, xtyp: pairXtype("List_" + arrSuffixOf(aX), "List_" + arrSuffixOf(bX)) , owned: true }
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
        let pX = pairXtype("Integer", elemX)
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(xc_pair_t));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_integer_t _ix" + u + " = " + iv + ";\n"
                 + "        xc_pair_t _pp" + u + " = xc_pair_make(&_ix" + u + ", sizeof(xc_integer_t), xstd_list_at(" + sv + ", " + iv + "), sizeof(" + elem + "));\n"
                 + "        xstd_list_push(" + rv + ", &_pp" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: "List_" + arrSuffixOf(pX) , owned: false }
    }
    if fld == "flatten" {
        // List<List<T>> -> List<T>
        let innerC = listElemCtype(elemX)
        let jv = "_j" + u
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + innerC + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_List_t _sub" + u + " = *(xc_List_t*)xstd_list_at(" + sv + ", " + iv + ");\n"
                 + "        for (xc_integer_t " + jv + " = 0; " + jv + " < xstd_list_len(_sub" + u + "); " + jv + " = " + jv + " + 1) xstd_list_push(" + rv + ", xstd_list_at(_sub" + u + ", " + jv + ")); } " + rv + "; })"
        return ExprRes { code: code, pos: q, xtyp: elemX , owned: false }
    }

    // ── lambda methods:  { [params =>] body } ──
    let close = matchBrace(toks, q)
    let arrow = lambdaArrow(toks, q + 1, close)
    let p0 = "it"
    let p1 = ""
    let bstart = q + 1
    if arrow >= 0 {
        let pi = q + 1
        let firstP = true
        while pi < arrow {
            if gkind(toks, pi) == 1 {
                if firstP { p0 = gtext(toks, pi)  firstP = false } else { p1 = gtext(toks, pi) }
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
        let bctx = addSym(addSym(ctx, p0, accX), p1, elemX)
        let body = genExpr(toks, bstart, bctx)
        let elDecl = "        " + elem + " " + p1 + " = " + elAt + ";\n"
        if fld == "fold" {
            let accC = xnameToCtype(accX)
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
        let accC = xnameToCtype(accX)
        let bctx = addSym(addSym(ctx, p0, accX), p1, elemX)
        let body = genExpr(toks, bstart, bctx)
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + accC + ")); " + accC + " " + p0 + " = " + argCode + ";\n"
                 + "      xstd_list_push(" + rv + ", &" + p0 + ");\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        " + elem + " " + p1 + " = " + elAt + "; " + p0 + " = (" + body.code + "); xstd_list_push(" + rv + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "List_" + arrSuffixOf(accX) , owned: false }
    }
    if fld == "mapIndexed" {
        // { i, x => body } — p0 = index (Integer), p1 = element
        let bctx = addSym(addSym(ctx, p0, "Integer"), p1, elemX)
        let body = genExpr(toks, bstart, bctx)
        let uc = xnameToCtype(body.xtyp)
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + uc + "));\n"
                 + "      for (xc_integer_t " + iv + " = 0; " + iv + " < xstd_list_len(" + sv + "); " + iv + " = " + iv + " + 1) {\n"
                 + "        xc_integer_t " + p0 + " = " + iv + "; " + elem + " " + p1 + " = " + elAt + ";\n"
                 + "        " + uc + " _v = (" + body.code + "); xstd_list_push(" + rv + ", &_v); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "List_" + arrSuffixOf(body.xtyp) , owned: false }
    }

    // single-param lambdas: p0 binds the element
    let bctx = addSym(ctx, p0, elemX)
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
        let keyC = xnameToCtype(body.xtyp)
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
        let uc = xnameToCtype(body.xtyp)
        let code = "({ " + declSv + "xc_List_t " + rv + " = xstd_list_new(sizeof(" + uc + "));\n      " + loopOpen
                 + "        " + uc + " _v = (" + body.code + "); xstd_list_push(" + rv + ", &_v); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "List_" + arrSuffixOf(body.xtyp) , owned: false }
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
        return ExprRes { code: code, pos: close + 1, xtyp: pairXtype(typ, typ) , owned: true }
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
        let sc = xnameToCtype(body.xtyp)
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
        let uc = listElemCtype(body.xtyp)
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
        let keyC = xnameToCtype(body.xtyp)
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
        let keyC = xnameToCtype(body.xtyp)
        let code = sortStmtExpr(declSv, sv, rv, iv, u, elem, p0, keyC, body.xtyp, body.code, fld == "sortedByDescending")
        return ExprRes { code: code, pos: close + 1, xtyp: typ , owned: false }
    }
    if fld == "groupBy" {
        // Map<K, List<T>> — bucket elements by a key
        let kc = xnameToCtype(body.xtyp)
        let kstr = strFlagFor(kc)
        let code = "({ " + declSv + "xc_Map_t " + rv + " = xstd_map_new(sizeof(" + kc + "), sizeof(xc_List_t), " + kstr + ");\n      " + loopOpen
                 + "        " + kc + " _k" + u + " = (" + body.code + ");\n"
                 + "        if (!xstd_map_has(" + rv + ", &_k" + u + ")) { xc_List_t _nl" + u + " = xstd_list_new(sizeof(" + elem + ")); xstd_map_put(" + rv + ", &_k" + u + ", &_nl" + u + "); }\n"
                 + "        xc_List_t _lst" + u + " = *(xc_List_t*)xstd_map_get(" + rv + ", &_k" + u + "); xstd_list_push(_lst" + u + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Map_" + arrSuffixOf(body.xtyp) + "_List_" + suf , owned: false }
    }
    if fld == "associateBy" {
        // Map<K, T> — key each element by a projection (last wins)
        let kc = xnameToCtype(body.xtyp)
        let kstr = strFlagFor(kc)
        let code = "({ " + declSv + "xc_Map_t " + rv + " = xstd_map_new(sizeof(" + kc + "), sizeof(" + elem + "), " + kstr + ");\n      " + loopOpen
                 + "        " + kc + " _k" + u + " = (" + body.code + "); xstd_map_put(" + rv + ", &_k" + u + ", &" + p0 + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Map_" + arrSuffixOf(body.xtyp) + "_" + suf , owned: false }
    }
    if fld == "associateWith" {
        // Map<T, V> — element is the key, value from a projection
        let vc = xnameToCtype(body.xtyp)
        let code = "({ " + declSv + "xc_Map_t " + rv + " = xstd_map_new(sizeof(" + elem + "), sizeof(" + vc + "), " + strF + ");\n      " + loopOpen
                 + "        " + vc + " _v" + u + " = (" + body.code + "); xstd_map_put(" + rv + ", &" + p0 + ", &_v" + u + "); } " + rv + "; })"
        return ExprRes { code: code, pos: close + 1, xtyp: "Map_" + suf + "_" + arrSuffixOf(body.xtyp) , owned: false }
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
        if gkind(toks, i) == 1 and gtext(toks, i) == "capture"
           and gkind(toks, i + 1) == 1 and gkind(toks, i + 2) == 108 {
            let nm = gtext(toks, i + 1)
            let ty = gtext(toks, i + 3)               // type name (ident or primitive keyword)
            if not strArrContains(seen, nm) {
                seen = appendString(seen, nm)
                out = out + "    " + cTy(xnameToCtype(ty)) + " " + nm + " = {0};\n"
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
        if gkind(toks, i) == 1 and gtext(toks, i) == "capture"
           and gkind(toks, i + 1) == 1 and gkind(toks, i + 2) == 108 {
            result = addSym(result, gtext(toks, i + 1), gtext(toks, i + 3))
        }
        i = i + 1
    }
    return result
}

mapper genPostfix(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let base = genPrimary(toks, pos, ctx)
    let code = base.code
    let typ = base.xtyp
    let bname = base.code
    let p = base.pos
    let cont = true
    while cont {
        let k = gkind(toks, p)
        if k == 107 or k == 129 {
            let fld = gtext(toks, p + 1)
            if isListXType(typ) and fld == "asSequence" {
                let fr = genSequenceChain(toks, p, code, listElemXName(typ), ctx, false, "", "", "")
                code = fr.code
                typ = fr.xtyp
                p = fr.pos
            } else {
            if isListXType(typ) and isListFunc(fld) {
                let fr = genListFunc(toks, p, code, typ, fld, ctx)
                code = fr.code
                typ = fr.xtyp
                p = fr.pos
            } else {
            if gkind(toks, p + 2) == 100 {
                if typ == "events:" {
                    // Built-in event facility (over the type-erased envelope).
                    let al = genArgs(toks, p + 2, ctx)
                    if fld == "dispatch" { code = "xc_event_dispatch(" + al.code + ")"  typ = "" }
                    if fld == "encode"   { code = "xc_event_encode(" + al.code + ")"    typ = "Json" }
                    if fld == "decode"   { code = "xc_event_decode(" + al.code + ")"    typ = "Event" }
                    if fld == "topic"    { code = "xstd_event_topic(" + al.code + ")"   typ = "String" }
                    if fld == "type"     { code = "xstd_event_type(" + al.code + ")"    typ = "String" }
                    if fld == "run"      { code = "xc_events_run()"  typ = "" }
                    if fld == "runAsync" { code = "xc_events_run_async()"  typ = "Thread" }
                    if fld == "stop"     { code = "xstd_eventq_close()"    typ = "" }
                    p = al.pos
                } else {
                if typ == "thread:" {
                    // Built-in thread facility: thread.channel() / thread.stopped()
                    let al = genArgs(toks, p + 2, ctx)
                    if fld == "channel" { code = "xstd_chan_new()"        typ = "Channel" }
                    if fld == "stopped" { code = "xstd_thread_stopped()"  typ = "Bool" }
                    p = al.pos
                } else {
                if typ == "Channel" {
                    let recv = code
                    if fld == "send" {
                        // ch.send(x): String passes through; a structured value
                        // (event/compound) is JSON-serialized; primitives stringify.
                        let dtoE = genExpr(toks, p + 3, ctx)
                        let payload = dtoE.code   // String / unknown: send as-is
                        if hasCodec(ctx.prog, dtoE.xtyp) {
                            payload = "xstd_json_stringify(xc_tojson_" + dtoE.xtyp + "(" + dtoE.code + "))"
                        } else {
                            if dtoE.xtyp == "Integer" or dtoE.xtyp == "Number" or dtoE.xtyp == "Bool" {
                                payload = toStrC(dtoE.code, dtoE.xtyp)
                            }
                        }
                        code = "xstd_chan_send(" + recv + ", " + payload + ")"
                        typ = ""
                        p = dtoE.pos
                        if gkind(toks, p) == 101 { p = p + 1 }   // )
                    } else {
                    if fld == "recv" {
                        if gkind(toks, p + 3) == 101 {
                            // ch.recv() -> raw String
                            code = "xstd_chan_recv(" + recv + ")"
                            typ = "String"
                            p = p + 4
                        } else {
                            // ch.recv(T) -> deserialize a structured T from JSON
                            let tn = gtext(toks, p + 3)
                            code = "xc_fromjson_" + tn + "(xstd_json_parse(xstd_chan_recv(" + recv + ")))"
                            typ = tn
                            p = p + 4
                            if gkind(toks, p) == 101 { p = p + 1 }   // )
                        }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "close" { code = "xstd_chan_close(" + recv + ")"  typ = "" }
                        p = al.pos
                    } }
                } else {
                if typ == "Thread" {
                    let al = genArgs(toks, p + 2, ctx)
                    if fld == "stop"    { code = "xstd_thread_stop("    + code + ")"  typ = "" }
                    if fld == "wait"    { code = "xstd_thread_wait("    + code + ")"  typ = "" }
                    if fld == "running" { code = "xstd_thread_running(" + code + ")"  typ = "Bool" }
                    p = al.pos
                } else {
                if isListXType(typ) {
                    let recv = code
                    let elem = listElemCtype(typ)
                    if fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_list_push(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""
                        p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "get" {
                        let al = genArgs(toks, p + 2, ctx)
                        code = "(*(" + elem + "*)xstd_list_at(" + recv + ", " + al.code + "))"
                        typ = listElemXName(typ)
                        p = al.pos
                    } else {
                    if fld == "set" or fld == "insert" {
                        let ie = genExpr(toks, p + 3, ctx)
                        let q = ie.pos
                        if gkind(toks, q) == 106 { q = q + 1 }   // ,
                        let ve = genExpr(toks, q, ctx)
                        let op = "xstd_list_set"
                        if fld == "insert" { op = "xstd_list_insert" }
                        code = op + "(" + recv + ", " + ie.code + ", (" + elem + "[]){ " + ve.code + " })"
                        typ = ""
                        p = ve.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "len"      { code = "xstd_list_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty"  { code = "(xstd_list_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "removeAt" { code = "xstd_list_removeat(" + recv + ", " + al.code + ")"  typ = "" }
                        if fld == "swap"     { code = "xstd_list_swap(" + recv + ", " + al.code + ")"  typ = "" }
                        if fld == "clear"    { code = "xstd_list_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    } } }
                } else {
                if isSetXType(typ) {
                    let recv = code
                    let elem = setElemCtype(typ)
                    if fld == "add" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_set_add(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""
                        p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "contains" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_set_contains(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = "Bool"
                        p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "remove" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_set_remove(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""
                        p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "len"     { code = "xstd_set_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_set_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_set_clear(" + recv + ")"  typ = "" }
                        if fld == "items"   { code = "xstd_set_items(" + recv + ")"  typ = "List_" + setElemSuffix(typ) }
                        p = al.pos
                    } } }
                } else {
                if isMapXType(typ) {
                    let recv = code
                    let kc = mapKeyCtype(typ)
                    let vc = mapValCtype(typ)
                    if fld == "put" {
                        let ke = genExpr(toks, p + 3, ctx)
                        let q = ke.pos
                        if gkind(toks, q) == 106 { q = q + 1 }   // ,
                        let ve = genExpr(toks, q, ctx)
                        code = "xstd_map_put(" + recv + ", (" + kc + "[]){ " + ke.code + " }, (" + vc + "[]){ " + ve.code + " })"
                        typ = ""
                        p = ve.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "get" {
                        let ke = genExpr(toks, p + 3, ctx)
                        code = "(*(" + vc + "*)xstd_map_get(" + recv + ", (" + kc + "[]){ " + ke.code + " }))"
                        typ = mapValXName(typ)
                        p = ke.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "getOr" {
                        let ke = genExpr(toks, p + 3, ctx)
                        let q = ke.pos
                        if gkind(toks, q) == 106 { q = q + 1 }   // ,
                        let de = genExpr(toks, q, ctx)
                        code = "(*(" + vc + "*)xstd_map_getor(" + recv + ", (" + kc + "[]){ " + ke.code + " }, (" + vc + "[]){ " + de.code + " }))"
                        typ = mapValXName(typ)
                        p = de.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "has" {
                        let ke = genExpr(toks, p + 3, ctx)
                        code = "xstd_map_has(" + recv + ", (" + kc + "[]){ " + ke.code + " })"
                        typ = "Bool"
                        p = ke.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                    if fld == "remove" {
                        let ke = genExpr(toks, p + 3, ctx)
                        code = "xstd_map_remove(" + recv + ", (" + kc + "[]){ " + ke.code + " })"
                        typ = ""
                        p = ke.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "len"     { code = "xstd_map_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_map_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_map_clear(" + recv + ")"  typ = "" }
                        if fld == "keys"    { code = "xstd_map_keys(" + recv + ")"  typ = "List_" + mapKeySuffix(typ) }
                        if fld == "values"  { code = "xstd_map_values(" + recv + ")"  typ = "List_" + mapValSuffix(typ) }
                        p = al.pos
                    } } } } }
                } else {
                if isStackXType(typ) {
                    let recv = code
                    let elem = stackElemCtype(typ)
                    let elemX = stackElemXName(typ)
                    if fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_stack_push(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""  p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "pop"     { code = "({ " + elem + " _pv" + int_to_string(p) + "; xstd_stack_pop(" + recv + ", &_pv" + int_to_string(p) + "); _pv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "peek"    { code = "(*(" + elem + "*)xstd_stack_peek(" + recv + "))"  typ = elemX }
                        if fld == "len"     { code = "xstd_stack_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_stack_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_stack_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    }
                } else {
                if isQueueXType(typ) {
                    let recv = code
                    let elem = queueElemCtype(typ)
                    let elemX = queueElemXName(typ)
                    if fld == "enqueue" or fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_queue_enqueue(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""  p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "dequeue" { code = "({ " + elem + " _qv" + int_to_string(p) + "; xstd_queue_dequeue(" + recv + ", &_qv" + int_to_string(p) + "); _qv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "pop"     { code = "({ " + elem + " _qv" + int_to_string(p) + "; xstd_queue_dequeue(" + recv + ", &_qv" + int_to_string(p) + "); _qv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "peek"    { code = "(*(" + elem + "*)xstd_queue_peek(" + recv + "))"  typ = elemX }
                        if fld == "len"     { code = "xstd_queue_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_queue_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_queue_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    }
                } else {
                if isSortedQueueXType(typ) {
                    let recv = code
                    let elem = sqElemCtype(typ)
                    let elemX = sqElemXName(typ)
                    if fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_pqueue_push(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""  p = ae.pos
                        if gkind(toks, p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "pop"     { code = "({ " + elem + " _hv" + int_to_string(p) + "; xstd_pqueue_pop(" + recv + ", &_hv" + int_to_string(p) + "); _hv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "peek"    { code = "(*(" + elem + "*)xstd_pqueue_peek(" + recv + "))"  typ = elemX }
                        if fld == "len"     { code = "xstd_pqueue_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_pqueue_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_pqueue_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    }
                } else {
                if typ == "HttpResponse" {
                    // res.send(dto): serialize via the DI-resolved WebTransport.
                    // res.sendStatus(code, msg) / res.sendText(code, body): plain text.
                    let recv = code
                    if fld == "send" {
                        let dtoE = genExpr(toks, p + 3, ctx)
                        code = "xstd_resp_set(" + recv + ", 200, xc_resolve_WebTransport().vtable->serialize(xc_resolve_WebTransport().self, xc_tojson_" + dtoE.xtyp + "(" + dtoE.code + ")), xc_string_from_cstr(\"application/json\"))"
                        p = dtoE.pos
                        if gkind(toks, p) == 101 { p = p + 1 }   // ')'
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        code = "xstd_resp_set(" + recv + ", " + al.code + ", xc_string_from_cstr(\"text/plain; charset=utf-8\"))"
                        p = al.pos
                    }
                    typ = ""
                } else {
                if typ == "HttpRequest" {
                    if fld == "parse" {
                        // req.parse(T): deserialize the body via WebTransport into a T.
                        let tn = gtext(toks, p + 3)
                        code = "xc_fromjson_" + tn + "(xc_resolve_WebTransport().vtable->deserialize(xc_resolve_WebTransport().self, xstd_req_body(" + code + ")))"
                        typ = tn
                        p = p + 4
                        if gkind(toks, p) == 101 { p = p + 1 }   // ')'
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        let recv = code
                        if fld == "query"  { code = "xstd_req_query("  + recv + ", " + al.code + ")" }
                        if fld == "header" { code = "xstd_req_header(" + recv + ", " + al.code + ")" }
                        if fld == "body"   { code = "xstd_req_body("   + recv + ")" }
                        if fld == "method" { code = "xstd_req_method(" + recv + ")" }
                        if fld == "path"   { code = "xstd_req_path("   + recv + ")" }
                        typ = "String"
                        p = al.pos
                    }
                } else {
                if typ == "PublisherService" and fld == "publish" {
                    // publish(topic, dto): wrap the typed DTO into an Event envelope.
                    let recv = code
                    let topicE = genExpr(toks, p + 3, ctx)
                    let q = topicE.pos
                    if gkind(toks, q) == 106 { q = q + 1 }   // ','
                    let dtoE = genExpr(toks, q, ctx)
                    code = recv + ".vtable->publish(" + recv + ".self, xc_wrap_" + dtoE.xtyp
                         + "(" + topicE.code + ", " + dtoE.code + "))"
                    typ = ""
                    p = dtoE.pos
                    if gkind(toks, p) == 101 { p = p + 1 }   // ')'
                } else {
                let al = genArgs(toks, p + 2, ctx)
                if startsWith2(typ, "atom:") {
                    let an = string_slice(typ, 5, string_len(typ))
                    if fld == "undo" {
                        // atom.undo(): revert to the previous state (no-op if none)
                        code = "xc_atom_" + an + "_undo()"
                        typ = atomStateTypeName(ctx.prog, an)
                    } else {
                    if fld == "canUndo" {
                        code = "(__atom_" + an + "_histlen > 0)"
                        typ = "Bool"
                    } else {
                        // atom.transition(args): push history, swap to the reducer result
                        let sep = ""
                        if string_len(al.code) > 0 { sep = ", " }
                        code = "(xc_atom_" + an + "_push(), __atom_" + an + " = xc_" + an + "__" + fld + "(__atom_" + an + sep + al.code + "))"
                        typ = atomStateTypeName(ctx.prog, an)
                    } }
                } else {
                if startsWith2(typ, "machinetype:") {
                    // Machine.start(...) -> xc_Machine__start(...)
                    let mmn = string_slice(typ, 12, string_len(typ))
                    code = "xc_" + mmn + "__" + fld + "(" + al.code + ")"
                    typ = mmn
                } else {
                if isMachineTypeC(ctx.prog, typ) {
                    if fld == "can" {
                        // m.can(transition, args?) -> xc_M__can_<transition>(value, args?)
                        // first arg is the transition NAME (a bare identifier).
                        let tname = gtext(toks, p + 3)
                        let q = p + 4
                        if gkind(toks, q) == 106 { q = q + 1 }   // skip ',' after name
                        let restargs = ""
                        let firstA = true
                        while gkind(toks, q) != 101 and gkind(toks, q) != 0 {
                            let a = genExpr(toks, q, ctx)
                            q = a.pos
                            if not firstA { restargs = restargs + ", " }
                            restargs = restargs + a.code
                            firstA = false
                            if gkind(toks, q) == 106 { q = q + 1 }
                        }
                        let csep = ""
                        if string_len(restargs) > 0 { csep = ", " }
                        code = "xc_" + typ + "__can_" + tname + "(" + code + csep + restargs + ")"
                        typ = "Bool"
                    } else {
                        // machineValue.transition(args) -> xc_M__transition(value, args)
                        let msep = ""
                        if string_len(al.code) > 0 { msep = ", " }
                        code = "xc_" + typ + "__" + fld + "(" + code + msep + al.code + ")"
                        if fld == "isTerminal" { typ = "Bool" }
                    }
                } else {
                if startsWith2(typ, "module:") and fld == "resolve" {
                    // Module.resolve(I) -> automatic interface resolver
                    code = "xc_resolve_" + al.firstRaw + "()"
                    typ = al.firstRaw
                } else {
                    if startsWith2(typ, "ns:") {
                        let path = string_slice(typ, 3, string_len(typ)) + "." + fld
                        code = builtinForPath(path) + "(" + al.code + ")"
                        typ = ""
                    } else {
                        if isInterface(ctx.prog, typ) {
                            let sep = ""
                            if string_len(al.code) > 0 { sep = ", " }
                            let mret = ifaceMethodRet(ctx.prog, typ, fld)
                            code = code + ".vtable->" + fld + "(" + code + ".self" + sep + al.code + ")"
                            typ = mret
                        } else {
                            if isTypeNameC(ctx.prog, typ) {
                                code = "xc_" + typ + "_" + fld + "(" + al.code + ")"
                                typ = ""
                            } else {
                                code = code + "." + fld + "(" + al.code + ")"
                                typ = ""
                            }
                        }
                    }
                }
                }
                }
                }
                p = al.pos
                }
                }
                }
                }
                }
                }
                }
                }
                }
                }
                }
                }
                }
            } else {
                if typ == "HttpRequest" {
                    // bare request accessors: req.path / req.method / req.body
                    if fld == "path"   { code = "xstd_req_path("   + code + ")" }
                    if fld == "method" { code = "xstd_req_method(" + code + ")" }
                    if fld == "body"   { code = "xstd_req_body("   + code + ")" }
                    typ = "String"
                } else {
                if startsWith2(typ, "atom:") {
                    // atom.current (or any field) -> the holder value
                    let an = string_slice(typ, 5, string_len(typ))
                    code = "__atom_" + an
                    typ = atomStateTypeName(ctx.prog, an)
                } else {
                if isMachineTypeC(ctx.prog, typ) and fld == "state" {
                    code = "xc_" + typ + "__state(" + code + ")"
                    typ = "String"
                } else {
                if startsWith2(typ, "ns:") {
                    typ = "ns:" + string_slice(typ, 3, string_len(typ)) + "." + fld
                } else {
                    if fld == "data" and startsWith2(typ, "arr_") {
                        // raw element pointer of an array fat pointer
                        code = code + ".data"
                        typ = "ptr:" + xnameFromArrSuffix(string_slice(typ, 4, string_len(typ)))
                    } else {
                        if isPairXType(typ) and (fld == "first" or fld == "second") {
                            // Pair<A,B>.first / .second — cast the stored value back to A/B.
                            let pex = pairElem(typ, 0)
                            if fld == "second" { pex = pairElem(typ, 1) }
                            code = "(*(" + xnameToCtype(pex) + "*)((" + code + ")." + fld + "))"
                            typ = pex
                        } else {
                        if typ == "String" and fld == "length" {
                            // string `.length` -> runtime length
                            code = "xstd_strlen(" + code + ")"
                            typ = "Integer"
                        } else {
                            let ft = fieldTypeNameC(ctx.prog, typ, fld)
                            code = code + "." + fld
                            typ = ft
                        }
                        }
                    }
                }
                }
                }
                }
                p = p + 2
            }
            }
            }
        } else {
            if k == 100 {
                let al = genArgs(toks, p, ctx)
                let _fx = lookupVar(ctx, bname)
                if isFnXType(_fx) {
                    // Closure call: cast the stored fn pointer to the signature
                    // recovered from the value's Fn(...) xtype and invoke it.
                    let rc = fnRetX(_fx)
                    let pcs = fnParamsX(_fx)
                    let sig = rc + "(*)(void*"
                    if string_len(pcs) > 0 { sig = sig + ", " + pcs }
                    sig = sig + ")"
                    let cargs = "(" + bname + ").env"
                    if string_len(al.code) > 0 { cargs = cargs + ", " + al.code }
                    code = "((" + sig + ")(" + bname + ").fn)(" + cargs + ")"
                    typ = ctypeToXName(rc)
                } else {
                if bname == "ok" {
                    // ok(x) -> build the enclosing function's Result with .ok=true
                    code = "(" + ctx.retCtype + "){ .ok = true, .value = " + al.code + " }"
                    typ = ""
                } else {
                if bname == "err" {
                    code = "(" + ctx.retCtype + "){ .ok = false, .err = " + al.code + " }"
                    typ = ""
                } else {
                if bname == "isOk" {
                    code = "((" + al.code + ").ok)"
                    typ = "Bool"
                } else {
                if bname == "isErr" {
                    code = "(!(" + al.code + ").ok)"
                    typ = "Bool"
                } else {
                if string_len(ctx.selfClass) > 0 and isSelfMethodC(ctx.prog, ctx.selfClass, bname) {
                    // Unqualified (or recursive) call to a sibling method.
                    let sargs = "self"
                    if string_len(al.code) > 0 { sargs = "self, " + al.code }
                    code = "xc_" + ctx.selfClass + "_" + bname + "_impl(" + sargs + ")"
                    typ = selfMethodRetXType(ctx.prog, ctx.selfClass, bname)
                } else {
                if isFuncNameC(ctx.prog, bname) {
                    if isAsyncFuncC(ctx.prog, bname) {
                        // async call: spawn a worker, yield a Future immediately
                        code = "xc_spawn_" + bname + "(" + al.code + ")"
                    } else {
                        code = "xc_" + bname + "(" + al.code + ")"
                    }
                    typ = funcRetXType(ctx.prog, bname)
                } else {
                    if isExternNameC(ctx.prog, bname) {
                        code = bname + "(" + al.code + ")"
                        typ = externRetXType(ctx.prog, bname)
                    } else {
                        code = bname + "(" + al.code + ")"
                        typ = ""
                    }
                }
                }
                }
                }
                }
                }
                }
                p = al.pos
            } else {
                if k == 104 {
                    let ie = genExpr(toks, p + 1, ctx)
                    let p2 = ie.pos
                    if gkind(toks, p2) == 105 { p2 = p2 + 1 }
                    if startsWith2(typ, "ptr:") {
                        // already a raw pointer (e.g. arr.data) — index directly
                        code = code + "[" + ie.code + "]"
                        typ = string_slice(typ, 4, string_len(typ))
                    } else {
                        if startsWith2(typ, "arr_") {
                            code = code + ".data[" + ie.code + "]"
                            typ = xnameFromArrSuffix(string_slice(typ, 4, string_len(typ)))
                        } else {
                            if endsWith2(typ, "[]") {
                                code = code + ".data[" + ie.code + "]"
                                typ = string_slice(typ, 0, string_len(typ) - 2)
                            } else {
                                code = code + ".data[" + ie.code + "]"
                                typ = ""
                            }
                        }
                    }
                    p = p2
                } else {
                    if k == 128 {
                        // ?? null-coalesce
                        let r = genPostfix(toks, p + 1, ctx)
                        code = "(" + code + ".has_value ? " + code + ".value : " + r.code + ")"
                        p = r.pos
                    } else {
                    if k == 209 and gkind(toks, p + 1) == 1 and isTypeNameC(ctx.prog, gtext(toks, p + 1)) {
                        // `<json> as T` — decode a Json value into a typed T (lenient
                        // coercion of string scalars). Reuses the derived JSON codec.
                        let tn = gtext(toks, p + 1)
                        code = "xc_fromjson_" + tn + "(" + code + ")"
                        typ = tn
                        p = p + 2
                    } else {
                    if k == 1 and gtext(toks, p) == "capture" and gkind(toks, p + 1) == 1 and gkind(toks, p + 2) == 108 {
                        // `<expr> capture name: Type` — bind the value to `name` (declared
                        // at the function top by the capture pre-scan) and yield it.
                        let nm = gtext(toks, p + 1)
                        code = "(" + nm + " = (" + code + "))"
                        p = p + 4                         // capture name : Type
                    } else {
                        // NOTE: a lone '?' (kind 127) is left unconsumed here so the
                        // statement layer can lower it as Result error-propagation.
                        cont = false
                    }
                    }
                    }
                }
            }
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: false }
}

// ── unary ─────────────────────────────────────────────────────────
mapper genUnary(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let k = gkind(toks, pos)
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
        if gkind(toks, pos + 1) == 1 and gtext(toks, pos + 1) == "all" {
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
        let k = gkind(toks, p)
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
        let k = gkind(toks, p)
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
    let k = gkind(toks, p)
    let isUntil  = (k == 1 and gtext(toks, p) == "until")
    let isDownTo = (k == 1 and gtext(toks, p) == "downTo")
    if k == 134 or isUntil or isDownTo {
        let right = genAdd(toks, p + 1, ctx)
        let endExpr = "(" + right.code + ") + 1"   // `..` inclusive
        let stepC = "1"
        if isUntil  { endExpr = "(" + right.code + ")" }
        if isDownTo { endExpr = "(" + right.code + ") - 1"  stepC = "-1" }
        let q = right.pos
        if gkind(toks, q) == 1 and gtext(toks, q) == "step" {   // optional `step n`
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
        let k = gkind(toks, p)
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
        if gkind(toks, p) == 225 {
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
        if gkind(toks, p) == 226 {
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
        if gkind(toks, p) == 1 and isInfixFnC(ctx.prog, gtext(toks, p)) {
            let fname = gtext(toks, p)
            let right = genAnd(toks, p + 1, ctx)
            code = "xc_" + fname + "(" + code + ", " + right.code + ")"
            typ = funcRetXType(ctx.prog, fname)
            p = right.pos
        } else {
            icont = false
        }
    }
    // `a to b` — build a Pair<A,B> (low precedence, right of `||`). Bind both
    // sides to addressable temporaries (works for struct and scalar types alike).
    if gkind(toks, p) == 1 and gtext(toks, p) == "to" {
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
        let bctx = addSym(ctx, nm, nmType)
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
            return StmtRes { code: line, ctx: addSym(ctx, name, ""), pos: e.pos + 1 }
        }
        let line = "    " + cdecl + " " + name + " = " + e.code + ";\n"
        return StmtRes { code: line, ctx: addSym(ctx, name, e.xtyp), pos: e.pos }
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
            let bctx = addSym(ctx, varName, listElemXName(it.xtyp))
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
            let bctx = addSym(ctx, varName, setElemXName(it.xtyp))
            let body = genStmts(toks, it.pos + 1, close, bctx)
            let code = "    { xc_List_t " + itv + " = xstd_set_items(" + it.code + ");\n"
                     + "      for (xc_integer_t " + idv + " = 0; " + idv + " < xstd_list_len(" + itv + "); " + idv + " = " + idv + " + 1) {\n"
                     + "        " + elem + " " + varName + " = *(" + elem + "*)xstd_list_at(" + itv + ", " + idv + ");\n"
                     + body + "      } }\n"
            return StmtRes { code: code, ctx: ctx, pos: close + 1 }
        }
        if it.xtyp == "Range" {
            // for i in <range> — a..b / until / downTo / step
            let bctx = addSym(ctx, varName, "Integer")
            let body = genStmts(toks, it.pos + 1, close, bctx)
            let code = "    { xc_range_t " + itv + " = " + it.code + ";\n"
                     + "      for (xc_integer_t " + varName + " = " + itv + ".start;\n"
                     + "           " + itv + ".step > 0 ? " + varName + " < " + itv + ".end : " + varName + " > " + itv + ".end;\n"
                     + "           " + varName + " = " + varName + " + " + itv + ".step) {\n"
                     + body + "      } }\n"
            return StmtRes { code: code, ctx: ctx, pos: close + 1 }
        }
        let bctx = addSym(ctx, varName, "")
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
        if pt.kind == 1 and isVariantNameC(ctx.prog, pt.text) {
            // sum-type variant pattern:  Variant [binding] -> body
            let sumN = sumOfVariant(ctx.prog, pt.text)
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
        if string_len(bindName) > 0 { bctx = addSym(ctx, bindName, "") }
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
                let bctx = withTag(addSym(mkGCtx(prog), varName, typeName), tag)
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
            let bctx = withTag(withRet(mkGCtx(prog), "void"), id)
            if nc > 0 {
                out = out + "    xc_parenv_" + id + "_t* __e = (xc_parenv_" + id + "_t*)__a;\n"
                let c = 0
                while c < nc {
                    let nm = stringArrGet(pp.caps, c)
                    out = out + "    xc_Channel_t " + nm + " = __e->" + nm + ";\n"
                    bctx = addSym(bctx, nm, "Channel")
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

// Refined-type aliases (typedef base) — must precede array typedefs.
// An alias whose target is an array/optional type (e.g. `type People = Person[]`).
// These reference xc_arr_*/xc_opt_* and so must be emitted AFTER those typedefs
// (see genAliasTypedefs); they are skipped by the array/opt/result/refined passes.
predicate isCompositeAlias(ts: TypeSpec) {
    if ts.isCompound { return false }
    return startsWith2(ts.baseCtype, "xc_arr_")
}

mapper genRefinedTypedefs(prog: Program) -> String {
    let out = "/* === Refined type aliases === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not ts.isCompound and not ts.isSum and not isCompositeAlias(ts) {
            out = out + "typedef " + ts.baseCtype + " xc_" + ts.name + "_t;\n"
        }
        i = i + 1
    }
    return out + "\n"
}

// Aliases to array/optional types, emitted after genArrTypedefs/genOptTypedefs
// so the target xc_arr_*/xc_opt_* typedefs already exist.
mapper genAliasTypedefs(prog: Program) -> String {
    let out = "/* === Array/optional type aliases === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if isCompositeAlias(ts) {
            out = out + "typedef " + ts.baseCtype + " xc_" + ts.name + "_t;\n"
        }
        i = i + 1
    }
    return out + "\n"
}

// Full compound struct bodies + sum-type tagged unions, emitted in declaration
// order so a type may embed any earlier-declared type by value.
mapper genCompoundBodies(prog: Program) -> String {
    let out = "/* === Compound + sum type bodies === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.isCompound {
            out = out + "struct xc_" + ts.name + "_s {\n"
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let field = stringArrGet(ts.fields, fi)
                let colonPos = findChar(field, 58)
                let fname = string_slice(field, 0, colonPos)
                let fctype = string_slice(field, colonPos + 1, string_len(field))
                out = out + "    " + fctype + " " + fname + ";\n"
                fi = fi + 1
            }
            out = out + "};\n"
        }
        if ts.isSum { out = out + sumBody(ts) }
        i = i + 1
    }
    return out + "\n"
}

// One sum type's tag #defines + tagged-union struct body.
mapper sumBody(ts: TypeSpec) -> String {
    let out = ""
    let vn = stringArrLen(ts.variants)
    let vi = 0
    while vi < vn {
        let v = stringArrGet(ts.variants, vi)
        let bar = findChar(v, 124)
        out = out + "#define xc_" + ts.name + "_" + string_slice(v, 0, bar) + " " + int_to_string(vi) + "\n"
        vi = vi + 1
    }
    out = out + "struct xc_" + ts.name + "_s {\n    int tag;\n"
    let anyFields = false
    vi = 0
    while vi < vn {
        let v = stringArrGet(ts.variants, vi)
        let bar = findChar(v, 124)
        if string_len(string_slice(v, bar + 1, string_len(v))) > 0 { anyFields = true }
        vi = vi + 1
    }
    if anyFields {
        out = out + "    union {\n"
        vi = 0
        while vi < vn {
            let v = stringArrGet(ts.variants, vi)
            let bar = findChar(v, 124)
            let vname = string_slice(v, 0, bar)
            let fstr = string_slice(v, bar + 1, string_len(v))
            if string_len(fstr) > 0 {
                out = out + "        struct { " + sumFieldsToC(fstr) + "} " + vname + ";\n"
            }
            vi = vi + 1
        }
        out = out + "    } u;\n"
    }
    return out + "};\n"
}

// Tagged-union bodies for sum types: an int tag plus a union of the payload
// structs (only variants that carry fields), and a #define per variant tag.
extern "C" {
    mapper findChar(s: String, c: Integer) -> Integer
    producer compile_c(cpath: String, binpath: String) -> Integer
}

mapper genForwardDecls(prog: Program) -> String {
    let out = "/* === Forward declarations === */\n"
    // Compound types (so array typedefs can use xc_T_t* before the full body)
    let t = 0
    let tn = typeSpecLen(prog.types)
    while t < tn {
        let ts = typeSpecGet(prog.types, t)
        if ts.isCompound {
            out = out + "typedef struct xc_" + ts.name + "_s xc_" + ts.name + "_t;\n"
        }
        if ts.isSum {
            out = out + "typedef struct xc_" + ts.name + "_s xc_" + ts.name + "_t;\n"
        }
        t = t + 1
    }
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        out = out + "typedef struct xc_" + cs.name + "_s xc_" + cs.name + "_t;\n"
        i = i + 1
    }
    let j = 0
    let m = ifaceSpecLen(prog.ifaces)
    while j < m {
        let is2 = ifaceSpecGet(prog.ifaces, j)
        out = out + "typedef struct xc_" + is2.name + "_vtable_s xc_" + is2.name + "_vtable_t;\n"
        out = out + "typedef struct xc_" + is2.name + "_s xc_" + is2.name + "_t;\n"
        j = j + 1
    }
    return out + "\n"
}

mapper genIfaceDecls(prog: Program) -> String {
    let out = "/* === Interfaces === */\n"
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        out = out + "struct xc_" + is2.name + "_vtable_s {\n"
        let mi = 0
        let mn = methodSpecLen(is2.methList)
        while mi < mn {
            let ms = methodSpecGet(is2.methList, mi)
            let pstr = ms.params
            if string_len(pstr) > 0 { pstr = ", " + pstr }
            out = out + "    " + ms.retCtype + " (*" + ms.name + ")(void* self" + pstr + ");\n"
            mi = mi + 1
        }
        out = out + "};\n"
        out = out + "struct xc_" + is2.name + "_s { void* self; const xc_" + is2.name + "_vtable_t* vtable; };\n\n"
        i = i + 1
    }
    return out + "\n"
}

// Default implementations for interface methods declared with a `{ ... }` body.
// A class that doesn't override the method gets this in its vtable slot. `self`
// is opaque here (the concrete type is unknown), so a default body cannot touch
// instance fields — it works over its parameters (and may return a constant).
mapper genIfaceDefaults(prog: Program) -> String {
    let out = "/* === Interface default methods === */\n"
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        let mi = 0
        let mn = methodSpecLen(is2.methList)
        while mi < mn {
            let ms = methodSpecGet(is2.methList, mi)
            if tokenArrLen(ms.bodyTokens) > 0 {
                let pstr = ms.params
                if string_len(pstr) > 0 { pstr = ", " + pstr }
                let tag = is2.name + "_" + ms.name
                out = out + hoistCatches(prog, ms.bodyTokens, tag)
                out = out + hoistParallel(prog, ms.bodyTokens, tag)
                out = out + hoistLambdas(prog, ms.bodyTokens, tag)
                out = out + "static " + ms.retCtype + " xc_" + is2.name + "_" + ms.name + "_default_impl(void* self_ptr" + pstr + ") {\n"
                out = out + "    (void)self_ptr;\n"
                let ctx = withTag(withRet(seedParams(mkGCtx(prog), ms.params), ms.retCtype), tag)
                out = out + genBody2(ms.bodyTokens, ctx)
                out = out + "}\n\n"
            }
            mi = mi + 1
        }
        i = i + 1
    }
    return out + "\n"
}

mapper genClassStructs(prog: Program) -> String {
    let out = "/* === Class structs === */\n"
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        out = out + "struct xc_" + cs.name + "_s {\n"
        let di = 0
        let dn = depSpecLen(cs.depList)
        while di < dn {
            let dep = depSpecGet(cs.depList, di)
            out = out + "    " + dep.ctype + " " + dep.name + ";\n"
            di = di + 1
        }
        out = out + "};\n\n"
        i = i + 1
    }
    return out + "\n"
}

// Find the concrete class bound to an interface in a module
mapper findBinding(prog: Program, moduleName: String, ifaceName: String) -> String {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        if mod.name == moduleName {
            let j = 0
            let m = bindSpecLen(mod.bindings)
            while j < m {
                let b = bindSpecGet(mod.bindings, j)
                if b.ifaceName == ifaceName {
                    return b.concreteName
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    return ""
}

mapper findScope(prog: Program, moduleName: String, ifaceName: String) -> String {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        if mod.name == moduleName {
            let j = 0
            let m = bindSpecLen(mod.bindings)
            while j < m {
                let b = bindSpecGet(mod.bindings, j)
                if b.ifaceName == ifaceName {
                    return b.scopeKind
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    return "transient"
}

// Find a class spec by name
mapper findClass(prog: Program, name: String) -> ClassSpec {
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        if cs.name == name {
            return cs
        }
        i = i + 1
    }
    return ClassSpec { name: "", implNames: [], depList: [], methList: [] }
}

predicate isInterface(prog: Program, name: String) {
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        if is2.name == name { return true }
        i = i + 1
    }
    return false
}

// Return type (X name) of interface method, or "" if not found.
// `predicate` methods return Bool.
mapper ifaceMethodRet(prog: Program, iface: String, method: String) -> String {
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        if is2.name == iface {
            let mi = 0
            let mn = methodSpecLen(is2.methList)
            while mi < mn {
                let ms = methodSpecGet(is2.methList, mi)
                if ms.name == method {
                    if ms.kind == "predicate" { return "Bool" }
                    return resolveX(prog, ctypeToXName(ms.retCtype))
                }
                mi = mi + 1
            }
        }
        i = i + 1
    }
    return ""
}

// ── Automatic dependency resolution ───────────────────────────────
predicate classImplements(cs: ClassSpec, iface: String) {
    let i = 0
    let n = stringArrLen(cs.implNames)
    while i < n {
        if stringArrGet(cs.implNames, i) == iface { return true }
        i = i + 1
    }
    return false
}

// All classes implementing interface I, in declaration order.
mapper implementorsOf(prog: Program, iface: String) -> String[] {
    let out: String[] = []
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        if classImplements(cs, iface) { out = appendString(out, cs.name) }
        i = i + 1
    }
    return out
}

// Concrete class explicitly bound to I in any module, or "".
mapper bindFor(prog: Program, iface: String) -> String {
    // `module Test` bindings are ignored in normal builds and take precedence in
    // test builds (XC_TEST), layered over `module App` (and any other module).
    let testMode = inTestMode()
    let i = 0
    let n = moduleSpecLen(prog.modules)
    let found = ""
    let testFound = ""
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let isTest = (mod.name == "Test")
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.ifaceName == iface {
                if isTest { testFound = b.concreteName } else { found = b.concreteName }
            }
            j = j + 1
        }
        i = i + 1
    }
    if testMode and string_len(testFound) > 0 { return testFound }
    return found
}

mapper bindScopeFor(prog: Program, iface: String) -> String {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    let found = ""
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.ifaceName == iface { found = b.scopeKind }
            j = j + 1
        }
        i = i + 1
    }
    return found
}

// The single chosen implementor of I: explicit bind wins; else the sole (or
// first) implementor; else "" when nothing implements I.
mapper chosenImpl(prog: Program, iface: String) -> String {
    let b = bindFor(prog, iface)
    if string_len(b) > 0 { return b }
    let impls = implementorsOf(prog, iface)
    if stringArrLen(impls) > 0 { return stringArrGet(impls, 0) }
    return ""
}

predicate isResolvable(prog: Program, iface: String) {
    if string_len(bindFor(prog, iface)) > 0 { return true }
    if stringArrLen(implementorsOf(prog, iface)) > 0 { return true }
    if string_len(configPathFor(prog, iface)) > 0 { return true }   // config-backed
    return false
}

// For `I or J`: bind wins; else the sole implementor other than J; else J.
mapper orChoose(prog: Program, iface: String, alt: String) -> String {
    let b = bindFor(prog, iface)
    if string_len(b) > 0 { return b }
    let impls = implementorsOf(prog, iface)
    let pick = ""
    let count = 0
    let i = 0
    let n = stringArrLen(impls)
    while i < n {
        let c = stringArrGet(impls, i)
        if c != alt {
            pick = c
            count = count + 1
        }
        i = i + 1
    }
    if count == 1 { return pick }
    return alt
}

mapper genVtablesAndCasters(prog: Program) -> String {
    let out = "/* === Method forward decls and vtables === */\n"
    // Forward-declare all _impl functions
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let ms = methodSpecGet(cs.methList, mi)
            if ms.kind != "creator" {
                let pstr = ms.params
                if string_len(pstr) > 0 { pstr = ", " + pstr }
                out = out + "static " + ms.retCtype + " xc_" + cs.name + "_" + ms.name + "_impl(void* self_ptr" + pstr + ");\n"
            }
            mi = mi + 1
        }
        i = i + 1
    }
    out = out + "\n"

    // Vtable instances + casters
    let ci = 0
    let cn2 = classSpecLen(prog.classes)
    while ci < cn2 {
        let cs = classSpecGet(prog.classes, ci)
        let ii = 0
        let iN = stringArrLen(cs.implNames)
        while ii < iN {
            let ifname = stringArrGet(cs.implNames, ii)
            // Find interface methods
            let ifSpec = IfaceSpec { name: "", extendsNames: [], methList: [] }
            let fi = 0
            let fn2 = ifaceSpecLen(prog.ifaces)
            while fi < fn2 {
                let cand = ifaceSpecGet(prog.ifaces, fi)
                if cand.name == ifname { ifSpec = cand }
                fi = fi + 1
            }
            out = out + "static const xc_" + ifname + "_vtable_t xc_" + cs.name + "_" + ifname + "_vtable = {\n"
            let mi = 0
            let mn = methodSpecLen(ifSpec.methList)
            while mi < mn {
                let ms = methodSpecGet(ifSpec.methList, mi)
                // The class's own impl if it overrides the method; otherwise the
                // interface's default impl (for methods with a default body).
                let target = "xc_" + cs.name + "_" + ms.name + "_impl"
                if countMethodName(cs, ms.name) == 0 and tokenArrLen(ms.bodyTokens) > 0 {
                    target = "xc_" + ifname + "_" + ms.name + "_default_impl"
                }
                out = out + "    ." + ms.name + " = (void*)" + target + ",\n"
                mi = mi + 1
            }
            out = out + "};\n"
            out = out + "static inline xc_" + ifname + "_t xc_" + cs.name + "_as_" + ifname + "(xc_" + cs.name + "_t* self) {\n"
            out = out + "    return (xc_" + ifname + "_t){ .self = self, .vtable = &xc_" + cs.name + "_" + ifname + "_vtable };\n"
            out = out + "}\n\n"
            ii = ii + 1
        }
        ci = ci + 1
    }
    return out + "\n"
}

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
    if isFnXType(ct) { return "xc_fn_t" }
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
    if isFnXType(ctype) { return string_slice(seg, 0, s) + "xc_fn_t" + string_slice(seg, lastSp, n) }
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
        result = addSym(result, dep.name, dep.ifaceName)
        i = i + 1
    }
    return result
}

mapper emitOneFunc(prog: Program, fs: FuncSpec) -> String {
    let tag = fs.name
    let capN = buildCapNames(fs.params, fs.fnDeps)
    let capX = buildCapXTypes(fs.params, fs.fnDeps)
    let out = hoistCatches(prog, fs.bodyTokens, tag)
    out = out + hoistParallel(prog, fs.bodyTokens, tag)
    out = out + hoistLambdas(prog, fs.bodyTokens, tag)
    out = out + hoistDelays(prog, fs.bodyTokens, tag, capN, capX)
    // `async` free functions: the body returns the inner T (the Future wrapper is
    // applied at the call site via xc_spawn_<name>).
    let isAsync = fs.isAsync
    let retC = fs.retCtype
    if isAsync { retC = asyncInnerCtype(fs) }
    out = out + "static " + cTy(retC) + " xc_" + fs.name + "(" + cSig(fs.params) + ") {\n"
    out = out + funcDepPrologue(prog, fs.fnDeps)
    out = out + captureDecls(fs.bodyTokens)
    let ctx = seedCaptures(withCaps(withTag(seedFuncDeps(withRet(seedParams(mkGCtx(prog), fs.params), retC), fs.fnDeps), tag), capN, capX), fs.bodyTokens)
    out = out + genBody2(fs.bodyTokens, ctx)
    out = out + "}\n\n"
    if isAsync { out = out + emitAsyncWrapper(prog, fs) }
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
            let bctx = withRet(seedParams(mkGCtx(prog), fs.params), fs.retCtype)
            out = out + genBody2(fs.bodyTokens, bctx)
            out = out + "}\n\n"
            let call = "xc_" + implName + "(" + argList + ")"
            if fs.hasWhere {
                let gctx = withRet(seedParams(mkGCtx(prog), fs.params), fs.retCtype)
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
            let k = gkind(outs, pos)
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
        if gkind(outs, pos) == 125 { pos = pos + 1 }
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
        let ctx = seedParams(mkGCtx(prog), t.params)
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
                out = out + "    " + t.retElem + "* __buf = __M > 0 ? (" + t.retElem + "*)malloc((xc_size_t)__M * sizeof(" + t.retElem + ")) : (" + t.retElem + "*)0;\n"
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
        result = addDep(result, dep.name, dep.ifaceName)
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
                let ctx = withTag(withRet(seedParams(seedDeps(mkGCtx(prog), cs), params), ret), cs.name + "_" + name)
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
                let ctx = withTag(withRet(seedFuncDeps(seedParams(mkGCtx(prog), ms.params), ms.fnDeps), ms.retCtype), tag)
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
                let ctx = withSelfClass(withTag(withRet(seedFuncDeps(seedParams(seedDeps(mkGCtx(prog), cs), ms.params), ms.fnDeps), ms.retCtype), tag), cs.name)
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

// Emit C statements that wire one dependency into `target` (e.g. "o->logger").
mapper wireDep(prog: Program, dep: DepSpec, target: String) -> String {
    let j = dep.ifaceName
    let form = dep.form

    if form == "list" {
        let impls = implementorsOf(prog, j)
        let nimp = stringArrLen(impls)
        let out = "    { xc_arr_" + j + "_t _a; _a.len = " + int_to_string(nimp) + "; _a.cap = " + int_to_string(nimp) + ";\n"
        if nimp == 0 {
            out = out + "      _a.data = (xc_" + j + "_t*)0;\n"
        } else {
            out = out + "      _a.data = (xc_" + j + "_t*)malloc(" + int_to_string(nimp) + " * sizeof(xc_" + j + "_t));\n"
            let k = 0
            while k < nimp {
                let impl = stringArrGet(impls, k)
                out = out + "      _a.data[" + int_to_string(k) + "] = xc_" + impl + "_as_" + j + "(xc_new_" + impl + "());\n"
                k = k + 1
            }
        }
        return out + "      " + target + " = _a; }\n"
    }

    if form == "where" {
        let impls = implementorsOf(prog, j)
        let nimp = stringArrLen(impls)
        let gctx = addSym(mkGCtx(prog), dep.name, j)
        let cond = genExpr(dep.whereTokens, 0, gctx)
        let out = "    { bool _ok = false;\n"
        let k = 0
        while k < nimp {
            let impl = stringArrGet(impls, k)
            out = out + "      if (!_ok) { xc_" + j + "_t " + dep.name + " = xc_" + impl + "_as_" + j + "(xc_new_" + impl + "());\n"
            out = out + "        if (" + cond.code + ") { " + target + " = " + dep.name + "; _ok = true; } }\n"
            k = k + 1
        }
        if nimp > 0 {
            let first = stringArrGet(impls, 0)
            out = out + "      if (!_ok) { " + target + " = xc_" + first + "_as_" + j + "(xc_new_" + first + "()); }\n"
        }
        return out + "    }\n"
    }

    if form == "or" {
        let chosen = orChoose(prog, j, dep.orAlt)
        if string_len(chosen) == 0 { return "    /* dep " + dep.name + ": unresolved */\n" }
        return "    " + target + " = xc_" + chosen + "_as_" + j + "(xc_new_" + chosen + "());\n"
    }

    if form == "opt" {
        if isResolvable(prog, j) {
            return "    " + target + ".has_value = true; " + target + ".value = xc_resolve_" + j + "();\n"
        }
        return "    /* optional dep " + dep.name + ": none */\n"
    }

    // single
    if isInterface(prog, j) {
        if isResolvable(prog, j) {
            return "    " + target + " = xc_resolve_" + j + "();\n"
        }
        return "    /* dep " + dep.name + ": no implementor of " + j + " */\n"
    }
    return "    /* dep " + dep.name + ": non-interface */\n"
}

// Forward declarations so constructors/resolvers can mutually recurse.
// Refined-type constraint checkers: xc_check_<T>(value) aborts on violation.
mapper genCheckFns(prog: Program) -> String {
    let out = "/* === Refined-type constraint checks === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not ts.isCompound {
            if ts.hasWhere {
                let base = ts.baseCtype
                let ctx = addSym(mkGCtx(prog), "value", ctypeToXName(base))
                let cond = genExpr(ts.whereTokens, 0, ctx)
                out = out + "static " + base + " xc_check_" + ts.name + "(" + base + " value) {\n"
                out = out + "    XC_CONSTRAINT_CHECK(" + cond.code + ", \"" + ts.name + "\");\n"
                out = out + "    return value;\n}\n"
            }
        }
        i = i + 1
    }
    return out + "\n"
}

mapper genCtorResolverFwd(prog: Program) -> String {
    let out = "/* === DI forward declarations === */\n"
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        out = out + "static xc_" + cs.name + "_t* xc_new_" + cs.name + "(void);\n"
        i = i + 1
    }
    let j = 0
    let m = ifaceSpecLen(prog.ifaces)
    while j < m {
        let is2 = ifaceSpecGet(prog.ifaces, j)
        out = out + "static xc_" + is2.name + "_t xc_resolve_" + is2.name + "(void);\n"
        j = j + 1
    }
    return out + "\n"
}

// Per-class heap constructor that auto-wires its dependencies.
mapper genConstructors(prog: Program) -> String {
    let out = "/* === DI constructors === */\n"
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        let cn = cs.name
        out = out + "static xc_" + cn + "_t* xc_new_" + cn + "(void) {\n"
        out = out + "    xc_" + cn + "_t* o = (xc_" + cn + "_t*)xc_obj_alloc(sizeof(xc_" + cn + "_t));\n"
        out = out + "    if (!o) abort();\n"
        out = out + "    memset(o, 0, sizeof(xc_" + cn + "_t));\n"
        let di = 0
        let dn = depSpecLen(cs.depList)
        while di < dn {
            let dep = depSpecGet(cs.depList, di)
            out = out + wireDep(prog, dep, "o->" + dep.name)
            di = di + 1
        }
        out = out + "    return o;\n}\n\n"
        i = i + 1
    }
    return out + "\n"
}

// Per-interface resolver: bind override or sole implementor; singleton or fresh.
// Config-backed implementors: a vtable whose methods read the parsed config tree
// by method name and decode into each method's return type.
mapper genConfigImpls(prog: Program) -> String {
    if not usesConfig(prog) { return "" }
    let out = "/* === Config-backed interface implementors === */\n"
    out = out + "extern xc_string_t file_read_all(xc_string_t);\n"
    out = out + "extern xc_Json_t xstd_json_parse(xc_string_t);\n"
    out = out + "extern xc_Json_t xstd_yaml_parse(xc_string_t);\n"
    out = out + "extern xc_Json_t xstd_json_get(xc_Json_t, xc_string_t);\n"
    out = out + "extern xc_string_t xstd_json_as_string(xc_Json_t);\n"
    out = out + "extern xc_number_t xstd_json_as_number(xc_Json_t);\n"
    out = out + "extern xc_bool_t xstd_json_as_bool(xc_Json_t);\n"
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        let ifn = is2.name
        if string_len(configPathFor(prog, ifn)) > 0 {
            let mn = methodSpecLen(is2.methList)
            let mi = 0
            while mi < mn {
                let ms = methodSpecGet(is2.methList, mi)
                let dec = jsonDecodeExpr(prog, ms.retCtype, "xstd_json_get(_t, xc_string_from_cstr(\"" + ms.name + "\"))")
                out = out + "static " + ms.retCtype + " xc_" + ifn + "__" + ms.name + "_cfg(void* self) {\n"
                out = out + "    xc_Json_t _t = (xc_Json_t)self; (void)_t;\n"
                if string_len(dec) > 0 {
                    out = out + "    return " + dec + ";\n"
                } else {
                    out = out + "    " + ms.retCtype + " _z; memset(&_z, 0, sizeof(_z)); return _z;\n"
                }
                out = out + "}\n"
                mi = mi + 1
            }
            out = out + "static const xc_" + ifn + "_vtable_t xc_" + ifn + "_cfg_vtable = {\n"
            mi = 0
            while mi < mn {
                let ms = methodSpecGet(is2.methList, mi)
                out = out + "    ." + ms.name + " = xc_" + ifn + "__" + ms.name + "_cfg,\n"
                mi = mi + 1
            }
            out = out + "};\n\n"
        }
        i = i + 1
    }
    return out
}

mapper genResolvers(prog: Program) -> String {
    let out = "/* === DI resolvers === */\n"
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        let ifn = is2.name
        let cfgp = configPathFor(prog, ifn)
        if string_len(cfgp) > 0 {
            // config-backed: parse the file once, return a fat ptr over the tree
            let parse = "xstd_yaml_parse(_src" + ifn + ")"
            if endsWith2(cfgp, ".json") { parse = "xstd_json_parse(_src" + ifn + ")" }
            out = out + "static xc_" + ifn + "_t xc_resolve_" + ifn + "(void) {\n"
            out = out + "    static xc_Json_t _cfg" + ifn + "; static bool _ci" + ifn + " = false;\n"
            out = out + "    if (!_ci" + ifn + ") { xc_string_t _src" + ifn + " = file_read_all(xc_string_from_cstr(\"" + cfgp + "\")); _cfg" + ifn + " = " + parse + "; _ci" + ifn + " = true; }\n"
            out = out + "    return (xc_" + ifn + "_t){ .self = (void*)_cfg" + ifn + ", .vtable = &xc_" + ifn + "_cfg_vtable };\n"
            out = out + "}\n\n"
            i = i + 1
        } else {
        out = out + "static xc_" + ifn + "_t xc_resolve_" + ifn + "(void) {\n"
        let chosen = chosenImpl(prog, ifn)
        if string_len(chosen) == 0 {
            out = out + "    xc_" + ifn + "_t _z; memset(&_z, 0, sizeof(_z)); return _z;\n"
        } else {
            if bindScopeFor(prog, ifn) == "singleton" {
                out = out + "    return xc_" + chosen + "_as_" + ifn + "(&xc_singleton_" + chosen + ");\n"
            } else {
                out = out + "    return xc_" + chosen + "_as_" + ifn + "(xc_new_" + chosen + "());\n"
            }
        }
        out = out + "}\n\n"
        i = i + 1
        }
    }
    return out + "\n"
}

mapper genSingletons(prog: Program) -> String {
    let out = "/* === Singleton storage === */\n"
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.scopeKind == "singleton" and string_len(b.configPath) == 0 {
                out = out + "static xc_" + b.concreteName + "_t xc_singleton_" + b.concreteName + ";\n"
                out = out + "static bool xc_singleton_" + b.concreteName + "_initialized = false;\n"
            }
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

mapper genSingletonInit(prog: Program) -> String {
    let out = "/* === Singleton init === */\n"
    out = out + "static void xc_init_singletons(void) {\n"
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.scopeKind == "singleton" and string_len(b.configPath) == 0 {
                let cn = b.concreteName
                // xc_new_ wires deps; singletons capture stable &storage addresses,
                // so initialisation order is irrelevant.
                out = out + "    if (!xc_singleton_" + cn + "_initialized) {\n"
                out = out + "        xc_singleton_" + cn + "_initialized = true;\n"
                out = out + "        xc_singleton_" + cn + " = *xc_new_" + cn + "();\n"
                out = out + "    }\n"
            }
            j = j + 1
        }
        i = i + 1
    }
    out = out + "}\n\n"
    return out
}

mapper genFactories(prog: Program) -> String {
    let out = "/* === DI factory functions === */\n"
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            let ifn = b.ifaceName
            let cn = b.concreteName
            let mname = mod.name
            let retType = ""
            if isInterface(prog, ifn) {
                retType = "xc_" + ifn + "_t"
            } else {
                retType = "xc_" + cn + "_t*"
            }
            out = out + "static " + retType + " xc_" + mname + "_resolve_" + ifn + "(void) {\n"
            if b.scopeKind == "singleton" and string_len(b.configPath) == 0 {
                if isInterface(prog, ifn) {
                    out = out + "    return xc_" + cn + "_as_" + ifn + "(&xc_singleton_" + cn + ");\n"
                } else {
                    out = out + "    return &xc_singleton_" + cn + ";\n"
                }
            } else {
                // Transient: heap-allocate and wire deps
                out = out + "    xc_" + cn + "_t* _obj = (xc_" + cn + "_t*)malloc(sizeof(xc_" + cn + "_t));\n"
                out = out + "    if (!_obj) abort();\n"
                out = out + "    memset(_obj, 0, sizeof(xc_" + cn + "_t));\n"
                // Wire deps
                let cls = findClass(prog, cn)
                let di = 0
                let dn = depSpecLen(cls.depList)
                while di < dn {
                    let dep = depSpecGet(cls.depList, di)
                    let depConc = findBinding(prog, mname, dep.ifaceName)
                    let depScope = findScope(prog, mname, dep.ifaceName)
                    if string_len(depConc) > 0 {
                        if isInterface(prog, dep.ifaceName) {
                            if depScope == "singleton" {
                                out = out + "    _obj->" + dep.name + " = xc_" + depConc + "_as_" + dep.ifaceName + "(&xc_singleton_" + depConc + ");\n"
                            } else {
                                out = out + "    xc_" + depConc + "_t* _dep_" + dep.name + " = (xc_" + depConc + "_t*)malloc(sizeof(xc_" + depConc + "_t));\n"
                                out = out + "    memset(_dep_" + dep.name + ", 0, sizeof(xc_" + depConc + "_t));\n"
                                out = out + "    _obj->" + dep.name + " = xc_" + depConc + "_as_" + dep.ifaceName + "(_dep_" + dep.name + ");\n"
                            }
                        }
                    }
                    di = di + 1
                }
                if isInterface(prog, ifn) {
                    out = out + "    return xc_" + cn + "_as_" + ifn + "(_obj);\n"
                } else {
                    out = out + "    return _obj;\n"
                }
            }
            out = out + "}\n\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// Return the last whitespace-separated word of a string (e.g. param name)
mapper lastWord(s: String) -> String {
    let n = string_len(s)
    let lastSp = 0 - 1
    let i = 0
    while i < n {
        if string_char_at(s, i) == 32 { lastSp = i }
        i = i + 1
    }
    return string_slice(s, lastSp + 1, n)
}

// Find a TypeSpec by X name (empty spec if absent).
mapper findTypeSpec(prog: Program, name: String) -> TypeSpec {
    let empty: String[] = []
    let none: Token[] = []
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == name { return ts }
        i = i + 1
    }
    return TypeSpec { name: "", isCompound: false, baseCtype: "", fields: empty, hasWhere: false, whereSrc: "", whereTokens: none, isSum: false, variants: [] }
}

// True if the app binds a non-default (non-LocalBus) PublisherService — i.e. an
// external transport, so emit should also serialize and publish on the wire.
predicate hasExternalPublisher(prog: Program) {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let m = moduleSpecGet(prog.modules, i)
        let j = 0
        let bn = bindSpecLen(m.bindings)
        while j < bn {
            let b = bindSpecGet(m.bindings, j)
            if b.ifaceName == "PublisherService" and b.concreteName != "LocalBus" { return true }
            j = j + 1
        }
        i = i + 1
    }
    return false
}

// JSON encode/decode expressions for one field ctype ("" = unsupported -> skip).
// Element C type of an array ctype "xc_arr_<suffix>_t".
mapper arrElemCtype(fct: String) -> String {
    let suf = string_slice(fct, 7, string_len(fct) - 2)   // strip "xc_arr_" and "_t"
    if suf == "string"  { return "xc_string_t" }
    if suf == "number"  { return "xc_number_t" }
    if suf == "integer" { return "xc_integer_t" }
    if suf == "bool"    { return "xc_bool_t" }
    if suf == "char"    { return "xc_char_t" }
    return "xc_" + suf + "_t"
}

mapper jsonEncodeExpr(prog: Program, fct: String, expr: String) -> String {
    match fct {
        "xc_string_t"  -> "xstd_json_string(" + expr + ")"
        "xc_number_t"  -> "xstd_json_number(" + expr + ")"
        "xc_integer_t" -> "xstd_json_number((xc_number_t)(" + expr + "))"
        "xc_bool_t"    -> "xstd_json_bool(" + expr + ")"
        "xc_Json_t"    -> expr
        _ -> {
            let xn = ctypeToXName(fct)
            if hasCodec(prog, xn) { return "xc_tojson_" + xn + "(" + expr + ")" }
            return ""
        }
    }
}
mapper jsonDecodeExpr(prog: Program, fct: String, getexpr: String) -> String {
    match fct {
        "xc_string_t"  -> "xstd_json_as_string(" + getexpr + ")"
        "xc_number_t"  -> "xstd_json_as_number(" + getexpr + ")"
        "xc_integer_t" -> "(xc_integer_t)xstd_json_as_number(" + getexpr + ")"
        "xc_bool_t"    -> "xstd_json_as_bool(" + getexpr + ")"
        "xc_Json_t"    -> getexpr
        _ -> {
            let xn = ctypeToXName(fct)
            if hasCodec(prog, xn) { return "xc_fromjson_" + xn + "(" + getexpr + ")" }
            return ""
        }
    }
}

// Derived JSON codec for one event type (used only at the process boundary).
mapper genOneCodec(prog: Program, t: String) -> String {
    let ts = findTypeSpec(prog, t)
    let to = "static xc_Json_t xc_tojson_" + t + "(xc_" + t + "_t v) {\n    xc_Json_t o = xstd_json_object();\n"
    let fr = "static xc_" + t + "_t xc_fromjson_" + t + "(xc_Json_t j) {\n    xc_" + t + "_t v; memset(&v, 0, sizeof(v));\n"
    let nf = stringArrLen(ts.fields)
    let i = 0
    while i < nf {
        let entry = stringArrGet(ts.fields, i)
        let colon = findChar(entry, 58)
        let fname = string_slice(entry, 0, colon)
        let fct = string_slice(entry, colon + 1, string_len(entry))
        let key = "xc_string_from_cstr(\"" + fname + "\")"
        if startsWith2(fct, "xc_arr_") {
            // array field -> a JSON array, element by element
            let ec = arrElemCtype(fct)
            let sx = int_to_string(i)
            let encE = jsonEncodeExpr(prog, ec, "v." + fname + ".data[__i" + sx + "]")
            let decE = jsonDecodeExpr(prog, ec, "xstd_json_at(__a" + sx + ", __i" + sx + ")")
            if string_len(encE) > 0 {
                to = to + "    { xc_Json_t __a" + sx + " = xstd_json_array();\n"
                   + "      for (xc_integer_t __i" + sx + " = 0; __i" + sx + " < (xc_integer_t)v." + fname + ".len; __i" + sx + "++)\n"
                   + "          xstd_json_push(__a" + sx + ", " + encE + ");\n"
                   + "      o = xstd_json_set(o, " + key + ", __a" + sx + "); }\n"
            }
            if string_len(decE) > 0 {
                fr = fr + "    { xc_Json_t __a" + sx + " = xstd_json_get(j, " + key + ");\n"
                   + "      xc_integer_t __n" + sx + " = xstd_json_length(__a" + sx + ");\n"
                   + "      " + fct + " __r" + sx + "; __r" + sx + ".len = (xc_size_t)__n" + sx + "; __r" + sx + ".cap = (xc_size_t)__n" + sx + ";\n"
                   + "      __r" + sx + ".data = __n" + sx + " > 0 ? (" + ec + "*)malloc((xc_size_t)__n" + sx + " * sizeof(" + ec + ")) : (" + ec + "*)0;\n"
                   + "      for (xc_integer_t __i" + sx + " = 0; __i" + sx + " < __n" + sx + "; __i" + sx + "++)\n"
                   + "          __r" + sx + ".data[__i" + sx + "] = " + decE + ";\n"
                   + "      v." + fname + " = __r" + sx + "; }\n"
            }
        } else {
            let enc = jsonEncodeExpr(prog, fct, "v." + fname)
            if string_len(enc) > 0 { to = to + "    o = xstd_json_set(o, " + key + ", " + enc + ");\n" }
            let dec = jsonDecodeExpr(prog, fct, "xstd_json_get(j, " + key + ")")
            if string_len(dec) > 0 { fr = fr + "    v." + fname + " = " + dec + ";\n" }
        }
        i = i + 1
    }
    to = to + "    return o;\n}\n"
    fr = fr + "    return v;\n}\n"
    return to + fr
}

// toJson/fromJson for every event type. Emitted but invoked only by external
// transports (in-process dispatch never serializes).
mapper genEventCodecs(prog: Program) -> String {
    // Codecs are derived for every event type, and — when std/web is in use — for
    // every compound type as well (so res.send(dto) / req.parse(T) auto-serialize).
    let types: String[] = []
    let ei = 0
    let ne = stringArrLen(prog.eventTypes)
    while ei < ne {
        types = appendString(types, stringArrGet(prog.eventTypes, ei))
        ei = ei + 1
    }
    if codecsEnabled(prog) {
        let ti = 0
        let tn = typeSpecLen(prog.types)
        while ti < tn {
            let ts = typeSpecGet(prog.types, ti)
            if ts.isCompound and not strArrContains(types, ts.name) {
                types = appendString(types, ts.name)
            }
            ti = ti + 1
        }
    }
    let nc = stringArrLen(types)
    if nc == 0 { return "" }
    let out = "/* === Derived JSON codecs (toJson/fromJson) === */\n"
    out = out + "extern xc_Json_t xstd_json_object(void);\n"
    out = out + "extern xc_Json_t xstd_json_set(xc_Json_t, xc_string_t, xc_Json_t);\n"
    out = out + "extern xc_Json_t xstd_json_string(xc_string_t);\n"
    out = out + "extern xc_Json_t xstd_json_number(xc_number_t);\n"
    out = out + "extern xc_Json_t xstd_json_bool(xc_bool_t);\n"
    out = out + "extern xc_Json_t xstd_json_get(xc_Json_t, xc_string_t);\n"
    out = out + "extern xc_string_t xstd_json_as_string(xc_Json_t);\n"
    out = out + "extern xc_number_t xstd_json_as_number(xc_Json_t);\n"
    out = out + "extern xc_bool_t xstd_json_as_bool(xc_Json_t);\n"
    out = out + "extern xc_Json_t xstd_json_array(void);\n"
    out = out + "extern xc_Json_t xstd_json_push(xc_Json_t, xc_Json_t);\n"
    out = out + "extern xc_integer_t xstd_json_length(xc_Json_t);\n"
    out = out + "extern xc_Json_t xstd_json_at(xc_Json_t, xc_integer_t);\n"
    out = out + "extern xc_string_t xstd_json_stringify(xc_Json_t);\n"
    out = out + "extern xc_Json_t xstd_json_parse(xc_string_t);\n"
    let i = 0
    while i < nc {
        let t = stringArrGet(types, i)
        out = out + "static xc_Json_t xc_tojson_" + t + "(xc_" + t + "_t);\n"
        out = out + "static xc_" + t + "_t xc_fromjson_" + t + "(xc_Json_t);\n"
        i = i + 1
    }
    i = 0
    while i < nc {
        out = out + genOneCodec(prog, stringArrGet(types, i))
        i = i + 1
    }
    return out + "\n"
}

// Forward declarations for the typed emitters and the inbound router, so call
// sites (in producer bodies) resolve before the definitions.
// Forward declarations for the per-type wrap helpers and the built-in event
// facility, so producer/consumer bodies resolve before the definitions.
mapper genEventFwd(prog: Program) -> String {
    let ne = stringArrLen(prog.eventTypes)
    if ne == 0 { return "" }
    let out = "/* === Event forward decls === */\n"
    let i = 0
    while i < ne {
        let t = stringArrGet(prog.eventTypes, i)
        out = out + "static xc_Event_t xc_wrap_" + t + "(xc_string_t, xc_" + t + "_t);\n"
        i = i + 1
    }
    out = out + "static void xc_event_dispatch(xc_Event_t);\n"
    out = out + "static xc_Json_t xc_event_encode(xc_Event_t);\n"
    out = out + "static xc_Event_t xc_event_decode(xc_string_t, xc_string_t, xc_Json_t);\n"
    if isInterface(prog, "ConsumerService") {
        out = out + "static void xc_events_run(void);\n"
    }
    out = out + "static xc_Thread_t xc_events_run_async(void);\n"
    return out + "\n"
}

// The typed event machinery: per-type envelope wrappers (heap-copy the DTO, no
// serialization), the dispatcher that routes an envelope to the typed listeners,
// and the encode/decode helpers + pump runner used by external transports.
mapper genEventDispatch(prog: Program) -> String {
    let ne = stringArrLen(prog.eventTypes)
    if ne == 0 { return "" }
    let out = "/* === Event dispatch (typed envelopes) === */\n"
    // per-type wrap helpers: heap-copy the value into an envelope.
    let i = 0
    while i < ne {
        let t = stringArrGet(prog.eventTypes, i)
        out = out + "static xc_Event_t xc_wrap_" + t + "(xc_string_t topic, xc_" + t + "_t v) {\n"
        out = out + "    xc_" + t + "_t* p = (xc_" + t + "_t*)malloc(sizeof(xc_" + t + "_t));\n"
        out = out + "    if (!p) abort();\n    *p = v;\n"
        out = out + "    return xstd_event_make(topic, xc_string_from_cstr(\"" + t + "\"), (void*)p);\n}\n"
        i = i + 1
    }
    // dispatcher: typed-listener trampolines + a topic/type match table.
    let disp = "static void xc_event_dispatch(xc_Event_t __e) {\n"
    disp = disp + "    xc_string_t __t = xstd_event_topic(__e);\n"
    disp = disp + "    xc_string_t __ty = xstd_event_type(__e);\n"
    disp = disp + "    void* __pl = xstd_event_payload(__e);\n"
    disp = disp + "    (void)__t; (void)__ty; (void)__pl;\n"
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let ms = methodSpecGet(cs.methList, mi)
            let pt = firstParamXType(ms.params)
            if ms.kind == "listener" and string_len(ms.topic) > 0 and isEventTypeC(prog, pt) {
                let tr = "xc_evtT_" + cs.name + "_" + ms.name
                out = out + "static void " + tr + "(xc_" + pt + "_t e) {\n"
                out = out + "    xc_" + cs.name + "_" + ms.name + "_impl((void*)xc_new_" + cs.name + "(), e);\n}\n"
                disp = disp + "    if (xc_string_eq(__t, xc_string_from_cstr(\"" + ms.topic + "\")) && xc_string_eq(__ty, xc_string_from_cstr(\"" + pt + "\"))) " + tr + "(*(xc_" + pt + "_t*)__pl);\n"
            }
            mi = mi + 1
        }
        ci = ci + 1
    }
    disp = disp + "}\n"
    out = out + disp
    // encode: payload -> Json (by type name), for external transports.
    out = out + "static xc_Json_t xc_event_encode(xc_Event_t __e) {\n"
    out = out + "    xc_string_t __ty = xstd_event_type(__e);\n    void* __pl = xstd_event_payload(__e);\n"
    let ei = 0
    while ei < ne {
        let t = stringArrGet(prog.eventTypes, ei)
        out = out + "    if (xc_string_eq(__ty, xc_string_from_cstr(\"" + t + "\"))) return xc_tojson_" + t + "(*(xc_" + t + "_t*)__pl);\n"
        ei = ei + 1
    }
    out = out + "    return (xc_Json_t)0;\n}\n"
    // decode: (topic, type, Json) -> envelope, for external transports.
    out = out + "static xc_Event_t xc_event_decode(xc_string_t topic, xc_string_t type, xc_Json_t payload) {\n"
    let di = 0
    while di < ne {
        let t = stringArrGet(prog.eventTypes, di)
        out = out + "    if (xc_string_eq(type, xc_string_from_cstr(\"" + t + "\"))) return xc_wrap_" + t + "(topic, xc_fromjson_" + t + "(payload));\n"
        di = di + 1
    }
    out = out + "    return xstd_event_make(topic, type, (void*)0);\n}\n"
    // the pump: resolve the bound ConsumerService and run it.
    if isInterface(prog, "ConsumerService") {
        out = out + "static void xc_events_run(void) {\n"
        out = out + "    xc_ConsumerService_t __c = xc_resolve_ConsumerService();\n"
        out = out + "    __c.vtable->run(__c.self);\n}\n"
    }
    // async pump: a worker thread that blocks on the queue and dispatches each
    // event to its typed listeners, until Events.stop() closes the queue.
    out = out + "static void* xc_events_pump(void* __a) {\n"
    out = out + "    (void)__a;\n"
    out = out + "    for (;;) {\n"
    out = out + "        xc_Event_t __e = xstd_eventq_pop_blocking();\n"
    out = out + "        if (!__e) break;\n"
    out = out + "        xc_event_dispatch(__e);\n"
    out = out + "    }\n"
    out = out + "    return (void*)0;\n}\n"
    out = out + "static xc_Thread_t xc_events_run_async(void) {\n"
    out = out + "    return xstd_thread_spawn(xc_events_pump, (void*)0);\n}\n"
    return out + "\n"
}

// std/web (handler model): the runtime hands each request a fresh mutable
// response. Every class implementing WebRequestHandler is a controller and is
// auto-registered (DI-wired) — no explicit bind. Controllers are tried in
// declaration order; the first whose handle sets the response wins. Routing is
// the `where`-overloaded handle methods inside each controller.
mapper genWebDispatch(prog: Program) -> String {
    if not webEnabled(prog) { return "" }
    let out = "/* === Web (WebRequestHandler controllers) === */\n"
    out = out + "static void xc_web_handle(xc_HttpRequest_t __req, xc_HttpResponse_t __res) {\n"
    let impls = implementorsOf(prog, "WebRequestHandler")
    let n = stringArrLen(impls)
    let i = 0
    while i < n {
        let c = stringArrGet(impls, i)
        out = out + "    { xc_WebRequestHandler_t __h = xc_" + c + "_as_WebRequestHandler(xc_new_" + c + "());\n"
        out = out + "      if (xstd_starts_with(xstd_req_path(__req), __h.vtable->getBaseUrl(__h.self))) {\n"
        out = out + "        __h.vtable->handle(__h.self, __req, __res);\n"
        out = out + "        if (xstd_resp_status(__res) != 0) return; } }\n"
        i = i + 1
    }
    out = out + "}\n"
    out = out + "static void xc_web_init(void) { xstd_web_set_handler(xc_web_handle); }\n\n"
    return out
}

// The source file path, so `assert` failures can report file:line.
mapper genSrcFileDef(srcPath: String) -> String {
    return "const char* xc_src_file = \"" + cEscape(srcPath) + "\";\n"
}

// `xi test` (XC_TEST=1) replaces the entry with a runner over the `test` cases:
// each runs isolated (a failed assert aborts that test, the rest continue),
// then a summary + nonzero exit on any failure.
mapper genTestRunner(prog: Program, srcPath: String) -> String {
    let out = genSrcFileDef(srcPath)
    let n = funcSpecLen(prog.tests)
    let i = 0
    while i < n {
        let t = funcSpecGet(prog.tests, i)
        out = out + hoistCatches(prog, t.bodyTokens, "test" + int_to_string(i))
        out = out + hoistParallel(prog, t.bodyTokens, "test" + int_to_string(i))
        out = out + hoistLambdas(prog, t.bodyTokens, "test" + int_to_string(i))
        out = out + "static void xc_test_body_" + int_to_string(i) + "(void) {\n"
        out = out + funcDepPrologue(prog, t.fnDeps)
        let ctx = withTag(seedFuncDeps(mkGCtx(prog), t.fnDeps), "test" + int_to_string(i))
        out = out + genBody2(t.bodyTokens, ctx)
        out = out + "}\n"
        i = i + 1
    }
    out = out + "/* === Test runner === */\n"
    out = out + "int main(int argc, char** argv) {\n"
    out = out + "    xc_init_singletons();\n"
    out = out + "    xc_atoms_init();\n"
    let j = 0
    while j < n {
        let t = funcSpecGet(prog.tests, j)
        out = out + "    xc_test_run(\"" + cEscape(t.name) + "\", xc_test_body_" + int_to_string(j) + ");\n"
        j = j + 1
    }
    out = out + "    return xc_test_summary();\n"
    out = out + "}\n"
    return out
}

mapper genEntry(prog: Program, srcPath: String) -> String {
    let es = prog.entrySpec
    let capN = buildCapNames(es.params, es.fnDeps)
    let capX = buildCapXTypes(es.params, es.fnDeps)
    let out = genSrcFileDef(srcPath)
    out = out + hoistCatches(prog, es.bodyTokens, "entry")
    out = out + hoistParallel(prog, es.bodyTokens, "entry")
    out = out + hoistLambdas(prog, es.bodyTokens, "entry")
    out = out + hoistDelays(prog, es.bodyTokens, "entry", capN, capX)
    out = out + "/* === Entry point === */\n"
    out = out + "int main(int argc, char** argv) {\n"
    out = out + "    xc_init_singletons();\n"
    out = out + "    xc_atoms_init();\n"
    if webEnabled(prog) { out = out + "    xc_web_init();\n" }
    out = out + "    xc_arr_string_t xc_args;\n"
    out = out + "    xc_args.len = (xc_size_t)argc;\n"
    out = out + "    xc_args.cap = (xc_size_t)argc;\n"
    out = out + "    xc_args.data = (xc_string_t*)malloc(argc * sizeof(xc_string_t));\n"
    out = out + "    for (int i = 0; i < argc; i++) xc_args.data[i] = xc_string_from_cstr(argv[i]);\n"
    out = out + funcDepPrologue(prog, es.fnDeps)
    let ctx = withCaps(withTag(seedFuncDeps(mkGCtx(prog), es.fnDeps), "entry"), capN, capX)
    if string_len(es.params) > 0 {
        let pname = lastWord(es.params)
        out = out + "    xc_arr_string_t " + pname + " = xc_args;\n"
        ctx = addSym(ctx, pname, "arr_string")
    }
    out = out + captureDecls(es.bodyTokens)
    ctx = seedCaptures(ctx, es.bodyTokens)
    out = out + genBody2(es.bodyTokens, ctx)
    // scheduled jobs: register each, then run the cron scheduler (blocks forever)
    let sn = funcSpecLen(prog.scheduled)
    if sn > 0 {
        let s = 0
        while s < sn {
            let job = funcSpecGet(prog.scheduled, s)
            out = out + "    xstd_sched_register((void(*)(void))xc_" + job.name + ", \"" + cEscape(job.topic) + "\");\n"
            s = s + 1
        }
        out = out + "    xstd_scheduler_run();\n"
    }
    out = out + "    return 0;\n"
    out = out + "}\n"
    return out
}

// Array typedefs for user types — use xc_T_t* (pointer), so only the
// forward declaration of T is required. Emit BEFORE compound bodies.
mapper genArrTypedefs(prog: Program) -> String {
    let out = "/* === User array typedefs === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not isCompositeAlias(ts) {
            out = out + "typedef struct { xc_" + ts.name + "_t* data; xc_size_t len; xc_size_t cap; } xc_arr_" + ts.name + "_t;\n"
            out = out + "typedef xc_List_t xc_List_" + ts.name + "_t;\n"   // List<ts> / Vec<ts>
            out = out + "typedef xc_Set_t xc_Set_" + ts.name + "_t;\n"     // Set<ts>
            out = out + "typedef xc_Stack_t xc_Stack_" + ts.name + "_t;\n" // Stack<ts>
            out = out + "typedef xc_Queue_t xc_Queue_" + ts.name + "_t;\n" // Queue<ts>
            out = out + "typedef xc_SortedQueue_t xc_SortedQueue_" + ts.name + "_t;\n"  // SortedQueue<ts>
            out = out + "typedef xc_Future_t xc_Future_" + ts.name + "_t;\n"  // Future<ts>
            // Map<primitive-key, ts> — one alias per primitive/String key type
            out = out + "typedef xc_Map_t xc_Map_integer_" + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_number_"  + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_bool_"    + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_string_"  + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_char_"    + ts.name + "_t;\n"
        }
        i = i + 1
    }
    // Arrays of interface fat pointers (for list deps `I[]`)
    let j = 0
    let m = ifaceSpecLen(prog.ifaces)
    while j < m {
        let is2 = ifaceSpecGet(prog.ifaces, j)
        out = out + "typedef struct { xc_" + is2.name + "_t* data; xc_size_t len; xc_size_t cap; } xc_arr_" + is2.name + "_t;\n"
        j = j + 1
    }
    return out + "\n"
}

// Optional typedefs embed xc_T_t by value, so they require the full type
// definition. Emit AFTER compound bodies / refined aliases.
mapper genOptTypedefs(prog: Program) -> String {
    let out = "/* === User optional typedefs === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not isCompositeAlias(ts) {
            out = out + "typedef struct { bool has_value; xc_" + ts.name + "_t value; } xc_opt_" + ts.name + "_t;\n"
        }
        i = i + 1
    }
    return out + "\n"
}

// Result<T> typedefs: { bool ok; T value; xc_string_t err; }
// Emitted for primitives and every user type, so `T!` is always available.
mapper genResTypedefs(prog: Program) -> String {
    let out = "/* === Result typedefs (T!) === */\n"
    out = out + "typedef struct { bool ok; xc_number_t value;  xc_string_t err; } xc_res_number_t;\n"
    out = out + "typedef struct { bool ok; xc_integer_t value; xc_string_t err; } xc_res_integer_t;\n"
    out = out + "typedef struct { bool ok; xc_bool_t value;    xc_string_t err; } xc_res_bool_t;\n"
    out = out + "typedef struct { bool ok; xc_string_t value;  xc_string_t err; } xc_res_string_t;\n"
    out = out + "typedef struct { bool ok; xc_char_t value;    xc_string_t err; } xc_res_char_t;\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not isCompositeAlias(ts) {
            out = out + "typedef struct { bool ok; xc_" + ts.name + "_t value; xc_string_t err; } xc_res_" + ts.name + "_t;\n"
        }
        i = i + 1
    }
    return out + "\n"
}

// extern "C" declarations (bare names — these resolve to C helpers/runtime)
mapper genExternDecls(prog: Program) -> String {
    let out = "/* === Extern C declarations === */\n"
    let i = 0
    let n = funcSpecLen(prog.externs)
    while i < n {
        let fs = funcSpecGet(prog.externs, i)
        out = out + "extern " + fs.retCtype + " " + fs.name + "(" + fs.params + ");\n"
        i = i + 1
    }
    return out + "\n"
}

// Forward declarations for all free functions and creators.
mapper genFuncForwardDecls(prog: Program) -> String {
    let out = "/* === Function forward declarations === */\n"
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let fs = funcSpecGet(prog.functions, i)
        let isAsync = fs.isAsync
        let retC = fs.retCtype
        if isAsync { retC = asyncInnerCtype(fs) }
        out = out + "static " + cTy(retC) + " xc_" + fs.name + "(" + cSig(fs.params) + ");\n"
        if isAsync { out = out + "static xc_Future_t xc_spawn_" + fs.name + "(" + cSig(fs.params) + ");\n" }
        i = i + 1
    }
    let s = 0
    let sn = funcSpecLen(prog.scheduled)
    while s < sn {
        out = out + "static void xc_" + funcSpecGet(prog.scheduled, s).name + "(void);\n"
        s = s + 1
    }
    return out + "\n"
}

mapper genHeader() -> String => "/* Generated by xc-bootstrap — X compiler written in X */\n#include \"runtime.h\"\n\n"

// Assign each `interrupt` type an integer id used for runtime handler matching.
mapper genInterruptDefs(prog: Program) -> String {
    let n = stringArrLen(prog.interrupts)
    if n == 0 { return "" }
    let out = "/* === Interrupt type ids === */\n"
    let i = 0
    while i < n {
        out = out + "#define XC_INT_" + stringArrGet(prog.interrupts, i) + " " + int_to_string(i) + "\n"
        i = i + 1
    }
    return out + "\n"
}

// Atom holders + transition prototypes (emitted before any use site).
mapper genAtomDecls(prog: Program) -> String {
    let out = "/* === Atom holders & transition prototypes === */\n"
    let i = 0
    let n = atomSpecLen(prog.atoms)
    while i < n {
        let a = atomSpecGet(prog.atoms, i)
        let st = "xc_" + a.stateTypeName + "_t"
        out = out + "static " + st + " __atom_" + a.name + ";\n"
        // Bounded history for undo()/time-travel (keeps the most recent states).
        out = out + "static " + st + " __atom_" + a.name + "_hist[256];\n"
        out = out + "static int __atom_" + a.name + "_histlen = 0;\n"
        out = out + "static void xc_atom_" + a.name + "_push(void) {\n"
        out = out + "    if (__atom_" + a.name + "_histlen == 256) { memmove(__atom_" + a.name + "_hist, __atom_" + a.name + "_hist + 1, 255 * sizeof(" + st + ")); __atom_" + a.name + "_histlen = 255; }\n"
        out = out + "    __atom_" + a.name + "_hist[__atom_" + a.name + "_histlen++] = __atom_" + a.name + ";\n}\n"
        out = out + "static " + st + " xc_atom_" + a.name + "_undo(void) {\n"
        out = out + "    if (__atom_" + a.name + "_histlen > 0) __atom_" + a.name + " = __atom_" + a.name + "_hist[--__atom_" + a.name + "_histlen];\n"
        out = out + "    return __atom_" + a.name + ";\n}\n"
        let j = 0
        let m = funcSpecLen(a.transitions)
        while j < m {
            let fs = funcSpecGet(a.transitions, j)
            out = out + "static " + cTy(fs.retCtype) + " xc_" + fs.name + "(" + cSig(fs.params) + ");\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// Atom transition bodies + the runtime initializer that seeds each holder.
mapper genAtomDefs(prog: Program) -> String {
    let out = "/* === Atom transitions === */\n"
    let i = 0
    let n = atomSpecLen(prog.atoms)
    while i < n {
        let a = atomSpecGet(prog.atoms, i)
        let j = 0
        let m = funcSpecLen(a.transitions)
        while j < m {
            out = out + emitOneFunc(prog, funcSpecGet(a.transitions, j))
            j = j + 1
        }
        i = i + 1
    }
    out = out + "static void xc_atoms_init(void) {\n"
    let k = 0
    while k < n {
        let a = atomSpecGet(prog.atoms, k)
        let e = genExpr(a.initToks, 0, mkGCtx(prog))
        out = out + "    __atom_" + a.name + " = " + e.code + ";\n"
        k = k + 1
    }
    return out + "}\n\n"
}

// Signature suffix after `self` for a transition's params ("" or ", <params>").
mapper machineSig(params: String) -> String {
    if string_len(params) > 0 { return ", " + params }
    return ""
}

// The legality condition for a transition: source-state match (&& guard).
mapper machineCond(prog: Program, m: MachineSpec, tr: MachineTransition) -> String {
    let cond = machineStateCond(m, tr.froms)
    if tr.hasGuard {
        let gctx = seedParams(mkGCtx(prog), tr.params)
        if m.hasData { gctx = addSym(gctx, "data", m.name + "Data") }
        cond = "(" + cond + ") && (" + genExpr(tr.guardTokens, 0, gctx).code + ")"
    }
    return cond
}

// Machine function prototypes (so use sites resolve regardless of order).
mapper genMachineDecls(prog: Program) -> String {
    let out = "/* === Machine function prototypes === */\n"
    let i = 0
    let n = machineSpecLen(prog.machines)
    while i < n {
        let m = machineSpecGet(prog.machines, i)
        let mn = m.name
        out = out + "static xc_" + mn + "_t xc_" + mn + "__start(void);\n"
        out = out + "static xc_string_t xc_" + mn + "__state(xc_" + mn + "_t self);\n"
        out = out + "static xc_bool_t xc_" + mn + "__isTerminal(xc_" + mn + "_t self);\n"
        let j = 0
        let tn = machineTransLen(m.transitions)
        while j < tn {
            let tr = machineTransGet(m.transitions, j)
            let sig = machineSig(tr.params)
            out = out + "static xc_" + mn + "_t xc_" + mn + "__" + tr.name + "(xc_" + mn + "_t self" + sig + ");\n"
            out = out + "static xc_bool_t xc_" + mn + "__can_" + tr.name + "(xc_" + mn + "_t self" + sig + ");\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// Machine implementations: start (seeds state + data), state-name, isTerminal,
// and per transition a guarded mover + a `can` predicate. Illegal moves (wrong
// source state or failed guard) signal IllegalTransition.
mapper genMachineDefs(prog: Program) -> String {
    let out = "/* === Machine implementations === */\n"
    let i = 0
    let n = machineSpecLen(prog.machines)
    while i < n {
        let m = machineSpecGet(prog.machines, i)
        let mn = m.name
        // start(): initial state + data initial values
        out = out + "static xc_" + mn + "_t xc_" + mn + "__start(void) {\n"
            + "    xc_" + mn + "_t __r; __r.__state = " + int_to_string(machineStateIndex(m, m.initial)) + ";\n"
        if m.hasData {
            let di = m.dataInit
            let dp = 0
            let ictx = mkGCtx(prog)
            while gkind(di, dp) != 0 {
                let fname = gtext(di, dp)
                dp = dp + 1
                if gkind(di, dp) == 111 { dp = dp + 1 }   // =
                let e = genExpr(di, dp, ictx)
                dp = e.pos
                out = out + "    __r.data." + fname + " = " + castEmptyArr(m, fname, e) + ";\n"
                if gkind(di, dp) == 106 { dp = dp + 1 }   // ,
            }
        }
        out = out + "    return __r;\n}\n"
        // state(): tag -> name
        out = out + "static xc_string_t xc_" + mn + "__state(xc_" + mn + "_t self) {\n"
        let si = 0
        let sn = stringArrLen(m.states)
        while si < sn {
            out = out + "    if (self.__state == " + int_to_string(si) + ") return xc_string_from_cstr(\"" + stringArrGet(m.states, si) + "\");\n"
            si = si + 1
        }
        out = out + "    return xc_string_from_cstr(\"?\");\n}\n"
        // isTerminal()
        let tcsv = ""
        let ti = 0
        let ttn = stringArrLen(m.terminals)
        while ti < ttn {
            if string_len(tcsv) > 0 { tcsv = tcsv + "," }
            tcsv = tcsv + stringArrGet(m.terminals, ti)
            ti = ti + 1
        }
        let tcond = "0"
        if string_len(tcsv) > 0 { tcond = machineStateCond(m, tcsv) }
        out = out + "static xc_bool_t xc_" + mn + "__isTerminal(xc_" + mn + "_t self) { return " + tcond + "; }\n"
        // a data-local declaration reused by guard/update bodies
        let dataLocal = ""
        if m.hasData { dataLocal = "    xc_" + mn + "Data_t data = self.data; (void)data;\n" }
        let j = 0
        let jn = machineTransLen(m.transitions)
        while j < jn {
            let tr = machineTransGet(m.transitions, j)
            let sig = machineSig(tr.params)
            let cond = machineCond(prog, m, tr)
            let toIdx = int_to_string(machineStateIndex(m, tr.toState))
            // update assignments (over the OLD data local; written to __r.data)
            let upd = ""
            if tr.hasUpdate {
                let ut = tr.updateTokens
                let up = 0
                let uctx = seedParams(mkGCtx(prog), tr.params)
                if m.hasData { uctx = addSym(uctx, "data", mn + "Data") }
                while gkind(ut, up) != 0 {
                    let fname = gtext(ut, up)
                    up = up + 1
                    if gkind(ut, up) == 108 { up = up + 1 }   // :
                    let e = genExpr(ut, up, uctx)
                    up = e.pos
                    upd = upd + "        __r.data." + fname + " = " + castEmptyArr(m, fname, e) + ";\n"
                    if gkind(ut, up) == 106 { up = up + 1 }   // ,
                }
            }
            // the mover
            out = out + "static xc_" + mn + "_t xc_" + mn + "__" + tr.name + "(xc_" + mn + "_t self" + sig + ") {\n"
                + dataLocal
                + "    if (" + cond + ") { xc_" + mn + "_t __r = self; __r.__state = " + toIdx + ";\n"
                + upd
                + "        return __r; }\n"
                + "    { xc_IllegalTransition_t __pl; __pl.from = xc_" + mn + "__state(self); __pl.to = xc_string_from_cstr(\"" + tr.toState + "\");\n"
                + "      xc_handler_t* __hh = xc_int_find(XC_INT_IllegalTransition);\n"
                + "      if (__hh == ((void*)0)) xc_int_unhandled(\"IllegalTransition\");\n"
                + "      if (!__hh->fn(&__pl)) longjmp(__hh->unwind, 1); }\n"
                + "    return self;\n}\n"
            // the can predicate
            out = out + "static xc_bool_t xc_" + mn + "__can_" + tr.name + "(xc_" + mn + "_t self" + sig + ") {\n"
                + dataLocal
                + "    return (" + cond + ");\n}\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// FFI build metadata from `extern "C"` directives: emit each `include "..."`
// as a real `#include`, plus a `/* XC-BUILD-FLAGS: ... */` marker that compile_c
// scans to extend the cc command line (link libs, -I/-L, pkg-config names).
mapper genBuildMeta(prog: Program) -> String {
    let out = ""
    let nf = stringArrLen(prog.cFlags)
    if nf > 0 {
        let flags = ""
        let i = 0
        while i < nf {
            if i > 0 { flags = flags + " " }
            flags = flags + stringArrGet(prog.cFlags, i)
            i = i + 1
        }
        out = out + "/* XC-BUILD-FLAGS: " + flags + " */\n"
    }
    let ni = stringArrLen(prog.cIncludes)
    let j = 0
    while j < ni {
        out = out + "#include " + stringArrGet(prog.cIncludes, j) + "\n"
        j = j + 1
    }
    if string_len(out) > 0 { out = out + "\n" }
    return out
}

mapper genAll(prog: Program, srcPath: String) -> String {
    let tail = genEntry(prog, srcPath)
    if inTestMode() and funcSpecLen(prog.tests) > 0 { tail = genTestRunner(prog, srcPath) }
    return genHeader()
         + genBuildMeta(prog)
         + genInterruptDefs(prog)
         + genForwardDecls(prog)
         + genRefinedTypedefs(prog)
         + genArrTypedefs(prog)
         + genAliasTypedefs(prog)
         + genCompoundBodies(prog)
         + genOptTypedefs(prog)
         + genResTypedefs(prog)
         + genEventCodecs(prog)
         + genExternDecls(prog)
         + genIfaceDecls(prog)
         + genClassStructs(prog)
         + genIfaceDefaults(prog)
         + genVtablesAndCasters(prog)
         + genCheckFns(prog)
         + genSingletons(prog)
         + genCtorResolverFwd(prog)
         + genConstructors(prog)
         + genConfigImpls(prog)
         + genResolvers(prog)
         + genSingletonInit(prog)
         + genFuncForwardDecls(prog)
         + genEventFwd(prog)
         + genAtomDecls(prog)
         + genMachineDecls(prog)
         + genFreeFunctions(prog)
         + genDecisionTables(prog)
         + genAtomDefs(prog)
         + genMachineDefs(prog)
         + genClassMethods(prog)
         + genEventDispatch(prog)
         + genWebDispatch(prog)
         + tail
}

