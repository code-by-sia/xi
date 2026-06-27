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
mapper Token[].kindAt(i: Integer) -> Integer => tokenArrGet(this, i).kind
mapper Token[].textAt(i: Integer) -> String => tokenArrGet(this, i).text

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
        let k = toks.kindAt(p)
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

mapper GCtx.withRet(ret: String) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: ret, fnTag: this.fnTag,
        selfClass: this.selfClass, capNames: this.capNames, capTypes: this.capTypes
    }
}

mapper GCtx.withTag(tag: String) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: this.retCtype, fnTag: tag,
        selfClass: this.selfClass, capNames: this.capNames, capTypes: this.capTypes
    }
}

// Mark the enclosing class so unqualified calls to sibling methods resolve to
// `xc_<Class>_<name>_impl(self, ...)`.
mapper GCtx.withSelfClass(cls: String) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: this.retCtype, fnTag: this.fnTag,
        selfClass: cls, capNames: this.capNames, capTypes: this.capTypes
    }
}

// Record the enclosing function's params+deps as the set capturable by a
// `runWithDelay { }` block (so its worker thread can see them by value).
mapper GCtx.withCaps(names: String[], types: String[]) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: this.retCtype, fnTag: this.fnTag,
        selfClass: this.selfClass, capNames: names, capTypes: types
    }
}

mapper GCtx.addSym(name: String, typ: String) -> GCtx {
    return GCtx {
        prog: this.prog,
        symNames: appendString(this.symNames, name),
        symTypes: appendString(this.symTypes, typ),
        depNames: this.depNames,
        depTypes: this.depTypes,
        retCtype: this.retCtype,
        fnTag: this.fnTag,
        selfClass: this.selfClass,
        capNames: this.capNames,
        capTypes: this.capTypes
    }
}

mapper GCtx.addDep(name: String, typ: String) -> GCtx {
    return GCtx {
        prog: this.prog,
        symNames: this.symNames,
        symTypes: this.symTypes,
        depNames: appendString(this.depNames, name),
        depTypes: appendString(this.depTypes, typ),
        retCtype: this.retCtype,
        fnTag: this.fnTag,
        selfClass: this.selfClass,
        capNames: this.capNames,
        capTypes: this.capTypes
    }
}

mapper GCtx.lookupVar(name: String) -> String {
    let i = 0
    let n = stringArrLen(this.symNames)
    while i < n {
        if stringArrGet(this.symNames, i) == name {
            return stringArrGet(this.symTypes, i)
        }
        i = i + 1
    }
    return ""
}

predicate GCtx.isDepNameC(name: String) {
    let i = 0
    let n = stringArrLen(this.depNames)
    while i < n {
        if stringArrGet(this.depNames, i) == name { return true }
        i = i + 1
    }
    return false
}

mapper GCtx.depTypeOf(name: String) -> String {
    let i = 0
    let n = stringArrLen(this.depNames)
    while i < n {
        if stringArrGet(this.depNames, i) == name {
            return stringArrGet(this.depTypes, i)
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
mapper Program.resolveX(xname: String) -> String {
    if xname == "String"  { return "String" }
    if xname == "Number"  { return "Number" }
    if xname == "Integer" { return "Integer" }
    if xname == "Bool"    { return "Bool" }
    if xname == "Char"    { return "Char" }
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
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

predicate Program.isModuleNameC(name: String) {
    let i = 0
    let n = moduleSpecLen(this.modules)
    while i < n {
        if moduleSpecGet(this.modules, i).name == name { return true }
        i = i + 1
    }
    return false
}

predicate Program.isFuncNameC(name: String) {
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        if funcSpecGet(this.functions, i).name == name { return true }
        i = i + 1
    }
    return false
}

predicate Program.isAtomNameC(name: String) {
    let i = 0
    let n = atomSpecLen(this.atoms)
    while i < n {
        if atomSpecGet(this.atoms, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper Program.atomStateTypeName(name: String) -> String {
    let i = 0
    let n = atomSpecLen(this.atoms)
    while i < n {
        let a = atomSpecGet(this.atoms, i)
        if a.name == name { return a.stateTypeName }
        i = i + 1
    }
    return ""
}

predicate Program.isMachineTypeC(name: String) {
    let i = 0
    let n = machineSpecLen(this.machines)
    while i < n {
        if machineSpecGet(this.machines, i).name == name { return true }
        i = i + 1
    }
    return false
}

// Is `name` (an X type name) a declared typed `event`?
predicate Program.isEventTypeC(name: String) {
    let i = 0
    let n = stringArrLen(this.eventTypes)
    while i < n {
        if stringArrGet(this.eventTypes, i) == name { return true }
        i = i + 1
    }
    return false
}

// Is `name` a declared compound (struct-like) type?
predicate Program.isCompoundTypeC(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == name and ts.isCompound { return true }
        i = i + 1
    }
    return false
}

// ── Sum / algebraic types ─────────────────────────────────────────
predicate Program.isSumTypeC(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == name and ts.isSum { return true }
        i = i + 1
    }
    return false
}

// The sum type that owns variant `vname` (or "" if none). Variant names must be
// globally unique across sum types.
mapper Program.sumOfVariant(vname: String) -> String {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
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

predicate Program.isVariantNameC(vname: String) => string_len(this.sumOfVariant(vname)) > 0

// The "f1:ct1,f2:ct2" field string for a variant ("" if it carries no payload).
mapper Program.variantFieldsC(sumName: String, vname: String) -> String {
    let ts = findTypeSpec(this, sumName)
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
predicate Program.webEnabled() {
    if not isInterface(this, "WebRequestHandler") { return false }
    return stringArrLen(implementorsOf(this, "WebRequestHandler")) > 0
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

predicate Program.usesThreads() {
    if tokensUseThread(this.entrySpec.bodyTokens) { return true }
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        if tokensUseThread(funcSpecGet(this.functions, i).bodyTokens) { return true }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(this.classes)
    while ci < cn {
        let cs = classSpecGet(this.classes, ci)
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
predicate Program.usesConfig() {
    let i = 0
    let n = moduleSpecLen(this.modules)
    while i < n {
        let mod = moduleSpecGet(this.modules, i)
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
mapper Program.configPathFor(ifn: String) -> String {
    let i = 0
    let n = moduleSpecLen(this.modules)
    let found = ""
    while i < n {
        let mod = moduleSpecGet(this.modules, i)
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
predicate Program.progUsesReadConfig() {
    if tokensHaveIdent(this.entrySpec.bodyTokens, "readConfig") { return true }
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n { if tokensHaveIdent(funcSpecGet(this.functions, i).bodyTokens, "readConfig") { return true }  i = i + 1 }
    let ti = 0
    let tn = funcSpecLen(this.tests)
    while ti < tn { if tokensHaveIdent(funcSpecGet(this.tests, ti).bodyTokens, "readConfig") { return true }  ti = ti + 1 }
    let ci = 0
    let cn = classSpecLen(this.classes)
    while ci < cn {
        let cs = classSpecGet(this.classes, ci)
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
predicate Program.progUsesAsDecode() {
    if tokensHaveKind(this.entrySpec.bodyTokens, 209) { return true }
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n { if tokensHaveKind(funcSpecGet(this.functions, i).bodyTokens, 209) { return true }  i = i + 1 }
    let ti = 0
    let tn = funcSpecLen(this.tests)
    while ti < tn { if tokensHaveKind(funcSpecGet(this.tests, ti).bodyTokens, 209) { return true }  ti = ti + 1 }
    let ci = 0
    let cn = classSpecLen(this.classes)
    while ci < cn {
        let cs = classSpecGet(this.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn { if tokensHaveKind(methodSpecGet(cs.methList, mi).bodyTokens, 209) { return true }  mi = mi + 1 }
        ci = ci + 1
    }
    return false
}
predicate Program.codecsEnabled() {
    return this.webEnabled() or this.usesThreads() or this.usesConfig() or this.progUsesReadConfig() or this.progUsesAsDecode()
}

predicate Program.hasCodec(xn: String) {
    if this.isEventTypeC(xn) { return true }
    if this.isCompoundTypeC(xn) and this.codecsEnabled() { return true }
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

mapper Program.funcRetXType(name: String) -> String {
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        let fs = funcSpecGet(this.functions, i)
        if fs.name == name {
            // `async` free function: callers receive a Future<T> over the inner T.
            // (A plain `-> Future<T>` already resolves to a Future xtype below.)
            if fs.isAsync {
                return futureXtypeFor(asyncInnerCtype(fs))
            }
            return this.resolveX(ctypeToXName(fs.retCtype))
        }
        i = i + 1
    }
    return ""
}

// Is `name` a method of class `cls`? Used to resolve unqualified (and recursive)
// calls inside a method body to a self-dispatched `xc_<cls>_<name>_impl` call.
predicate Program.isSelfMethodC(cls: String, name: String) {
    let i = 0
    let n = classSpecLen(this.classes)
    while i < n {
        let cs = classSpecGet(this.classes, i)
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

mapper Program.selfMethodRetXType(cls: String, name: String) -> String {
    let i = 0
    let n = classSpecLen(this.classes)
    while i < n {
        let cs = classSpecGet(this.classes, i)
        if cs.name == cls {
            let mi = 0
            let mn = methodSpecLen(cs.methList)
            while mi < mn {
                let ms = methodSpecGet(cs.methList, mi)
                if ms.name == name { return this.resolveX(ctypeToXName(ms.retCtype)) }
                mi = mi + 1
            }
        }
        i = i + 1
    }
    return ""
}

predicate Program.isExternNameC(name: String) {
    let i = 0
    let n = funcSpecLen(this.externs)
    while i < n {
        if funcSpecGet(this.externs, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper Program.externRetXType(name: String) -> String {
    let i = 0
    let n = funcSpecLen(this.externs)
    while i < n {
        let fs = funcSpecGet(this.externs, i)
        if fs.name == name { return this.resolveX(ctypeToXName(fs.retCtype)) }
        i = i + 1
    }
    return ""
}

predicate Program.isTypeNameC(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        if typeSpecGet(this.types, i).name == name { return true }
        i = i + 1
    }
    let j = 0
    let m = classSpecLen(this.classes)
    while j < m {
        if classSpecGet(this.classes, j).name == name { return true }
        j = j + 1
    }
    return false
}

// Is `name` a refined type carrying a `where` constraint?
predicate Program.isRefinedConstrained(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
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
mapper Program.fieldCheckFn(typeName: String, field: String) -> String {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == typeName {
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let fentry = stringArrGet(ts.fields, fi)
                let colon = findChar(fentry, 58)
                if string_slice(fentry, 0, colon) == field {
                    let fctype = string_slice(fentry, colon + 1, string_len(fentry))
                    let xname = ctypeToXName(fctype)
                    if this.isRefinedConstrained(xname) { return "xc_check_" + xname }
                    return ""
                }
                fi = fi + 1
            }
        }
        i = i + 1
    }
    return ""
}

mapper Program.fieldTypeNameC(typeName: String, field: String) -> String {
    // Result<T> fields: .ok is Bool, .err is String, .value is T.
    if field == "ok"  { return "Bool" }
    if field == "err" { return "String" }
    if startsWith2(typeName, "res_") and field == "value" {
        let elem = string_slice(typeName, 4, string_len(typeName))
        return this.resolveX(xnameFromArrSuffix(elem))
    }
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == typeName {
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let fentry = stringArrGet(ts.fields, fi)
                let colon = findChar(fentry, 58)
                let fname = string_slice(fentry, 0, colon)
                if fname == field {
                    let fctype = string_slice(fentry, colon + 1, string_len(fentry))
                    return this.resolveX(ctypeToXName(fctype))
                }
                fi = fi + 1
            }
        }
        i = i + 1
    }
    return ""
}

