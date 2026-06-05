// xc code generator — Program -> C99
// ── Expression / statement codegen from token stream ─────────────
// Converts a Token[] body into C code string.

// ── Expression / statement code generator ────────────────────────
// A recursive-descent generator that walks body tokens and emits C,
// tracking a small symbol table for type-aware dispatch.

type ExprRes = { code: String, pos: Integer, xtyp: String }
type GArgs   = { code: String, pos: Integer, firstRaw: String }

type GCtx = {
    prog:     Program,
    symNames: String[],
    symTypes: String[],
    depNames: String[],
    depTypes: String[],
    retCtype: String,
    fnTag:    String        // mangled name of the enclosing fn (for catch helpers)
}

type StmtRes = { code: String, ctx: GCtx, pos: Integer }

// ── token access helpers ─────────────────────────────────────────
mapper gkind(toks: Token[], i: Integer) -> Integer {
    return tokenArrGet(toks, i).kind
}
mapper gtext(toks: Token[], i: Integer) -> String {
    return tokenArrGet(toks, i).text
}

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
creator mkGCtx(prog: Program) -> GCtx {
    return GCtx { prog: prog, symNames: [], symTypes: [], depNames: [], depTypes: [], retCtype: "", fnTag: "" }
}

mapper withRet(ctx: GCtx, ret: String) -> GCtx {
    return GCtx {
        prog: ctx.prog, symNames: ctx.symNames, symTypes: ctx.symTypes,
        depNames: ctx.depNames, depTypes: ctx.depTypes, retCtype: ret, fnTag: ctx.fnTag
    }
}

mapper withTag(ctx: GCtx, tag: String) -> GCtx {
    return GCtx {
        prog: ctx.prog, symNames: ctx.symNames, symTypes: ctx.symTypes,
        depNames: ctx.depNames, depTypes: ctx.depTypes, retCtype: ctx.retCtype, fnTag: tag
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
        fnTag: ctx.fnTag
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
        fnTag: ctx.fnTag
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
    if ctype == "xc_string_t"  { return "String" }
    if ctype == "xc_number_t"  { return "Number" }
    if ctype == "xc_integer_t" { return "Integer" }
    if ctype == "xc_bool_t"    { return "Bool" }
    if ctype == "xc_char_t"    { return "Char" }
    if ctype == "xc_size_t"    { return "Size" }
    let n = string_len(ctype)
    if n > 5 {
        return string_slice(ctype, 3, n - 2)
    }
    return ""
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

// std/web's handler model is active when at least one class implements
// WebRequestHandler (controllers are auto-registered — no explicit bind needed).
predicate webEnabled(prog: Program) {
    if not isInterface(prog, "WebRequestHandler") { return false }
    return stringArrLen(implementorsOf(prog, "WebRequestHandler")) > 0
}

// A JSON codec (xc_tojson_/xc_fromjson_) is emitted for this X type: every
// event type, plus (when web is in use) every compound type.
predicate hasCodec(prog: Program, xn: String) {
    if isEventTypeC(prog, xn) { return true }
    if webEnabled(prog) and isCompoundTypeC(prog, xn) { return true }
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

mapper funcRetXType(prog: Program, name: String) -> String {
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let fs = funcSpecGet(prog.functions, i)
        if fs.name == name { return resolveX(prog, ctypeToXName(fs.retCtype)) }
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
    if path == "system.stdout.writeln" { return "xc_stdout_writeln" }
    if path == "system.stdout.write"   { return "xc_stdout_write" }
    if path == "system.stderr.writeln" { return "xc_stderr_writeln" }
    if path == "system.stdin.readLine" { return "xc_stdin_readline" }
    if path == "system.process.exit"   { return "xc_process_exit" }
    return "0 /* unknown builtin */"
}

// X type name -> C element type
mapper xnameToCtype(xname: String) -> String {
    if xname == "String"  { return "xc_string_t" }
    if xname == "Number"  { return "xc_number_t" }
    if xname == "Integer" { return "xc_integer_t" }
    if xname == "Bool"    { return "xc_bool_t" }
    if xname == "Char"    { return "xc_char_t" }
    return "xc_" + xname + "_t"
}

// X type name -> array typedef suffix
mapper arrSuffixOf(xname: String) -> String {
    if xname == "String"  { return "string" }
    if xname == "Number"  { return "number" }
    if xname == "Integer" { return "integer" }
    if xname == "Bool"    { return "bool" }
    if xname == "Char"    { return "char" }
    return xname
}

// array typedef suffix -> element X type name
mapper xnameFromArrSuffix(suf: String) -> String {
    if suf == "string"  { return "String" }
    if suf == "number"  { return "Number" }
    if suf == "integer" { return "Integer" }
    if suf == "bool"    { return "Bool" }
    if suf == "char"    { return "Char" }
    return suf
}

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
    if k == 260 { return "xc_number_t" }
    if k == 261 { return "xc_integer_t" }
    if k == 262 { return "xc_bool_t" }
    if k == 263 { return "xc_string_t" }
    if k == 264 { return "xc_char_t" }
    if k == 265 { return "void" }
    if k == 266 { return "xc_size_t" }
    if k == 267 { return "const char*" }
    return ""
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

// coerce a C expression to a string value for concatenation
mapper toStrC(code: String, typ: String) -> String {
    if typ == "String" { return code }
    if typ == "Integer" { return "xc_integer_to_string(" + code + ")" }
    if typ == "Bool" { return "xc_bool_to_string(" + code + ")" }
    if typ == "Number" { return "xc_number_to_string(" + code + ")" }
    return "xc_number_to_string((xc_number_t)(" + code + "))"
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
    return ExprRes { code: out, pos: p, xtyp: typeName }
}

// ── primary ───────────────────────────────────────────────────────
mapper genPrimary(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let k = gkind(toks, pos)
    let txt = gtext(toks, pos)
    // `empty T` — the zero value of T (struct all-zero, array empty, ...).
    // Contextual: only when `empty` starts a primary AND is followed by a type
    // (so `bytes.empty()` and any var/field named `empty` still work).
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
            return ExprRes { code: "(" + ctype + "){0}", pos: tp, xtyp: gtext(toks, pos + 1) }
        }
    }
    if k == 2 { return ExprRes { code: txt + "LL", pos: pos + 1, xtyp: "Integer" } }
    if k == 3 { return ExprRes { code: txt, pos: pos + 1, xtyp: "Number" } }
    if k == 4 { return ExprRes { code: "xc_string_from_cstr(\"" + txt + "\")", pos: pos + 1, xtyp: "String" } }
    if k == 236 { return ExprRes { code: "true", pos: pos + 1, xtyp: "Bool" } }
    if k == 237 { return ExprRes { code: "false", pos: pos + 1, xtyp: "Bool" } }
    if k == 254 { return ExprRes { code: "{0}", pos: pos + 1, xtyp: "" } }
    if k == 253 { return ExprRes { code: "input", pos: pos + 1, xtyp: "" } }
    if k == 243 { return ExprRes { code: "value", pos: pos + 1, xtyp: lookupVar(ctx, "value") } }
    if k == 238 { return ExprRes { code: "self", pos: pos + 1, xtyp: "self" } }
    if k == 100 {
        let inner = genExpr(toks, pos + 1, ctx)
        let p2 = inner.pos
        if gkind(toks, p2) == 101 { p2 = p2 + 1 }
        return ExprRes { code: "(" + inner.code + ")", pos: p2, xtyp: inner.xtyp }
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
            return ExprRes { code: "{0}", pos: p, xtyp: "emptyarr" }
        }
        let arrType = "xc_arr_" + arrSuffixOf(firstX) + "_t"
        let elemCtype = xnameToCtype(firstX)
        let code = "(" + arrType + "){ .data = (" + elemCtype + "[]){ " + out
                 + " }, .len = " + int_to_string(count) + ", .cap = " + int_to_string(count) + " }"
        return ExprRes { code: code, pos: p, xtyp: arrSuffixOf(firstX) + "[]" }
    }
    if k == 1 {
        if gkind(toks, pos + 1) == 102 and isTypeNameC(ctx.prog, txt) {
            return genTypeLiteral(toks, pos, ctx)
        }
        if isDepNameC(ctx, txt) {
            return ExprRes { code: "self->" + txt, pos: pos + 1, xtyp: depTypeOf(ctx, txt) }
        }
        if txt == "system" {
            return ExprRes { code: "system", pos: pos + 1, xtyp: "ns:system" }
        }
        if txt == "Events" {
            // built-in event facility: Events.dispatch/encode/decode/topic/type/run
            return ExprRes { code: "", pos: pos + 1, xtyp: "events:" }
        }
        if isModuleNameC(ctx.prog, txt) {
            return ExprRes { code: txt, pos: pos + 1, xtyp: "module:" + txt }
        }
        if isAtomNameC(ctx.prog, txt) {
            return ExprRes { code: "__atom_" + txt, pos: pos + 1, xtyp: "atom:" + txt }
        }
        if isMachineTypeC(ctx.prog, txt) {
            return ExprRes { code: txt, pos: pos + 1, xtyp: "machinetype:" + txt }
        }
        return ExprRes { code: txt, pos: pos + 1, xtyp: lookupVar(ctx, txt) }
    }
    return ExprRes { code: txt, pos: pos + 1, xtyp: "" }
}

// ── postfix:  .field  .method(args)  (call)  [index] ──────────────
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
                    p = al.pos
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
                    // atom.transition(args): swap the holder to the reducer result
                    let an = string_slice(typ, 5, string_len(typ))
                    let sep = ""
                    if string_len(al.code) > 0 { sep = ", " }
                    code = "(__atom_" + an + " = xc_" + an + "__" + fld + "(__atom_" + an + sep + al.code + "))"
                    typ = atomStateTypeName(ctx.prog, an)
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
                p = p + 2
            }
        } else {
            if k == 100 {
                let al = genArgs(toks, p, ctx)
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
                if isFuncNameC(ctx.prog, bname) {
                    code = "xc_" + bname + "(" + al.code + ")"
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
                        // NOTE: a lone '?' (kind 127) is left unconsumed here so the
                        // statement layer can lower it as Result error-propagation.
                        cont = false
                    }
                }
            }
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ }
}

// ── unary ─────────────────────────────────────────────────────────
mapper genUnary(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let k = gkind(toks, pos)
    if k == 119 {
        let r = genUnary(toks, pos + 1, ctx)
        return ExprRes { code: "(-" + r.code + ")", pos: r.pos, xtyp: r.xtyp }
    }
    if k == 126 or k == 227 {
        let r = genUnary(toks, pos + 1, ctx)
        return ExprRes { code: "(!" + r.code + ")", pos: r.pos, xtyp: "Bool" }
    }
    if k == 231 { return genUnary(toks, pos + 1, ctx) }
    if k == 233 { return genUnary(toks, pos + 1, ctx) }
    if k == 251 { return genUnary(toks, pos + 1, ctx) }
    if k == 123 or k == 124 {
        let r = genUnary(toks, pos + 1, ctx)
        return ExprRes { code: "(&" + r.code + ")", pos: r.pos, xtyp: r.xtyp }
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
    return ExprRes { code: code, pos: p, xtyp: typ }
}

// ── additive (with string concat) ────────────────────────────────
mapper genAdd(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genMul(toks, pos, ctx)
    let code = left.code
    let typ = left.xtyp
    let p = left.pos
    let cont = true
    while cont {
        let k = gkind(toks, p)
        if k == 118 {
            let right = genMul(toks, p + 1, ctx)
            if typ == "String" or right.xtyp == "String" {
                code = "xc_string_concat(" + toStrC(code, typ) + ", " + toStrC(right.code, right.xtyp) + ")"
                typ = "String"
            } else {
                code = "(" + code + " + " + right.code + ")"
            }
            p = right.pos
        } else {
            if k == 119 {
                let right = genMul(toks, p + 1, ctx)
                code = "(" + code + " - " + right.code + ")"
                typ = "Number"
                p = right.pos
            } else {
                cont = false
            }
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ }
}

// ── comparison ────────────────────────────────────────────────────
mapper genCmp(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let left = genAdd(toks, pos, ctx)
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
    return ExprRes { code: code, pos: p, xtyp: typ }
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
    return ExprRes { code: code, pos: p, xtyp: typ }
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
    return ExprRes { code: code, pos: p, xtyp: typ }
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
        let bctx = addSym(ctx, nm, "")
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
        } } } } }
        if gkind(toks, p) == 109 { p = p + 1 }   // ->
        let bctx = ctx
        if string_len(bindName) > 0 { bctx = addSym(ctx, bindName, "") }
        let bindLine = ""
        if string_len(bindName) > 0 {
            bindLine = "        __auto_type " + bindName + " = " + subj + ";\n"
        }
        let bodyCode = ""
        if gkind(toks, p) == 102 {
            let close = matchBrace(toks, p)
            bodyCode = genStmts(toks, p + 1, close, bctx)
            p = close + 1
        } else {
            let be = genExpr(toks, p, bctx)
            bodyCode = "        " + be.code + ";\n"
            p = be.pos
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
                out = out + "    if (" + cond + ") {\n" + bodyCode + "    }\n"
            } else {
                out = out + "    else if (" + cond + ") {\n" + bodyCode + "    }\n"
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

// ── Code generator ────────────────────────────────────────────────

mapper mangle(name: String) -> String {
    return name   // in X, names are already valid C identifiers (no dots in this context)
}

mapper indent(s: String) -> String {
    return "    " + s
}

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
        if not ts.isCompound and not isCompositeAlias(ts) {
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

// Full compound struct bodies (named structs, matching forward declarations).
mapper genCompoundBodies(prog: Program) -> String {
    let out = "/* === Compound struct bodies === */\n"
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
        i = i + 1
    }
    return out + "\n"
}

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
    let i = 0
    let n = moduleSpecLen(prog.modules)
    let found = ""
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.ifaceName == iface { found = b.concreteName }
            j = j + 1
        }
        i = i + 1
    }
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
                out = out + "    ." + ms.name + " = (void*)xc_" + cs.name + "_" + ms.name + "_impl,\n"
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
mapper genBody2(toks: Token[], ctx: GCtx) -> String {
    return genStmts(toks, 0, tokenArrLen(toks), ctx)
}

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
    let out = hoistCatches(prog, fs.bodyTokens, tag)
    out = out + "static " + fs.retCtype + " xc_" + fs.name + "(" + fs.params + ") {\n"
    out = out + funcDepPrologue(prog, fs.fnDeps)
    let ctx = withTag(seedFuncDeps(withRet(seedParams(mkGCtx(prog), fs.params), fs.retCtype), fs.fnDeps), tag)
    out = out + genBody2(fs.bodyTokens, ctx)
    return out + "}\n\n"
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
                out = out + "static " + ms.retCtype + " xc_" + cs.name + "_" + ms.name + "(" + ms.params + ") {\n"
                let ctx = withTag(withRet(seedParams(mkGCtx(prog), ms.params), ms.retCtype), tag)
                out = out + genBody2(ms.bodyTokens, ctx)
                out = out + "}\n\n"
            } else {
                let pstr = ms.params
                if string_len(pstr) > 0 { pstr = ", " + pstr }
                out = out + hoistCatches(prog, ms.bodyTokens, tag)
                // Overloaded (multiple same-named, or `where`-guarded) methods emit
                // per-overload bodies + a dispatcher; otherwise a single _impl.
                let overloaded = countMethodName(cs, ms.name) > 1 or ms.hasWhere
                let implName = "xc_" + cs.name + "_" + ms.name + "_impl"
                if overloaded {
                    implName = "xc_" + cs.name + "_" + ms.name + "_ovl" + int_to_string(methodOrdinal(cs, mi)) + "_impl"
                }
                out = out + "static " + ms.retCtype + " " + implName + "(void* self_ptr" + pstr + ") {\n"
                out = out + "    xc_" + cs.name + "_t* self = (xc_" + cs.name + "_t*)self_ptr;\n"
                let ctx = withTag(withRet(seedParams(seedDeps(mkGCtx(prog), cs), ms.params), ms.retCtype), tag)
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
        out = out + "    xc_" + cn + "_t* o = (xc_" + cn + "_t*)malloc(sizeof(xc_" + cn + "_t));\n"
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
mapper genResolvers(prog: Program) -> String {
    let out = "/* === DI resolvers === */\n"
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        let ifn = is2.name
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
            if b.scopeKind == "singleton" {
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
            if b.scopeKind == "singleton" {
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
            if b.scopeKind == "singleton" {
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
    return TypeSpec { name: "", isCompound: false, baseCtype: "", fields: empty, hasWhere: false, whereSrc: "", whereTokens: none }
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
    if fct == "xc_string_t"  { return "xstd_json_string(" + expr + ")" }
    if fct == "xc_number_t"  { return "xstd_json_number(" + expr + ")" }
    if fct == "xc_integer_t" { return "xstd_json_number((xc_number_t)(" + expr + "))" }
    if fct == "xc_bool_t"    { return "xstd_json_bool(" + expr + ")" }
    if fct == "xc_Json_t"    { return expr }
    let xn = ctypeToXName(fct)
    if hasCodec(prog, xn) { return "xc_tojson_" + xn + "(" + expr + ")" }
    return ""
}
mapper jsonDecodeExpr(prog: Program, fct: String, getexpr: String) -> String {
    if fct == "xc_string_t"  { return "xstd_json_as_string(" + getexpr + ")" }
    if fct == "xc_number_t"  { return "xstd_json_as_number(" + getexpr + ")" }
    if fct == "xc_integer_t" { return "(xc_integer_t)xstd_json_as_number(" + getexpr + ")" }
    if fct == "xc_bool_t"    { return "xstd_json_as_bool(" + getexpr + ")" }
    if fct == "xc_Json_t"    { return getexpr }
    let xn = ctypeToXName(fct)
    if hasCodec(prog, xn) { return "xc_fromjson_" + xn + "(" + getexpr + ")" }
    return ""
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
    if webEnabled(prog) {
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
        out = out + "      __h.vtable->handle(__h.self, __req, __res);\n"
        out = out + "      if (xstd_resp_status(__res) != 0) return; }\n"
        i = i + 1
    }
    out = out + "}\n"
    out = out + "static void xc_web_init(void) { xstd_web_set_handler(xc_web_handle); }\n\n"
    return out
}

mapper genEntry(prog: Program) -> String {
    let es = prog.entrySpec
    let out = hoistCatches(prog, es.bodyTokens, "entry")
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
    let ctx = withTag(mkGCtx(prog), "entry")
    if string_len(es.params) > 0 {
        let pname = lastWord(es.params)
        out = out + "    xc_arr_string_t " + pname + " = xc_args;\n"
        ctx = addSym(ctx, pname, "arr_string")
    }
    out = out + genBody2(es.bodyTokens, ctx)
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
        out = out + "static " + fs.retCtype + " xc_" + fs.name + "(" + fs.params + ");\n"
        i = i + 1
    }
    return out + "\n"
}

mapper genHeader() -> String {
    return "/* Generated by xc-bootstrap — X compiler written in X */\n#include \"runtime.h\"\n\n"
}

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
        out = out + "static xc_" + a.stateTypeName + "_t __atom_" + a.name + ";\n"
        let j = 0
        let m = funcSpecLen(a.transitions)
        while j < m {
            let fs = funcSpecGet(a.transitions, j)
            out = out + "static " + fs.retCtype + " xc_" + fs.name + "(" + fs.params + ");\n"
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
                out = out + "    __r.data." + fname + " = " + e.code + ";\n"
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
                    upd = upd + "        __r.data." + fname + " = " + e.code + ";\n"
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

mapper genAll(prog: Program) -> String {
    return genHeader()
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
         + genVtablesAndCasters(prog)
         + genCheckFns(prog)
         + genSingletons(prog)
         + genCtorResolverFwd(prog)
         + genConstructors(prog)
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
         + genEntry(prog)
}

