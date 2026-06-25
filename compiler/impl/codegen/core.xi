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

