// xc parser — token stream -> Program (spec structs)
// ── Parser state ─────────────────────────────────────────────────
// The parser is functional: each parse function takes (tokens, pos)
// and returns a result struct with the new position.

type PState = { tokens: Token[], pos: Integer }

creator mkPState(tokens: Token[]) -> PState {
    return PState { tokens: tokens, pos: 0 }
}

// Peek at the current token
mapper peek(ps: PState) -> Token {
    let i = ps.pos
    let n = tokenArrLen(ps.tokens)
    if i >= n { return Token { kind: 0, text: "", line: 0 } }
    return tokenArrGet(ps.tokens, i)
}

// Peek ahead by offset
mapper peekAt(ps: PState, offset: Integer) -> Token {
    let i = ps.pos + offset
    let n = tokenArrLen(ps.tokens)
    if i >= n { return Token { kind: 0, text: "", line: 0 } }
    return tokenArrGet(ps.tokens, i)
}

// Advance position
mapper advance(ps: PState) -> PState {
    return PState { tokens: ps.tokens, pos: ps.pos + 1 }
}

// Check current token kind
predicate check(ps: PState, kind: Integer) {
    return peek(ps).kind == kind
}

// Match (consume) if kind matches; returns new state or same state
type MatchResult = { ps: PState, matched: Bool, text: String }

mapper match_tok(ps: PState, kind: Integer) -> MatchResult {
    if peek(ps).kind == kind {
        let tok = peek(ps)
        return MatchResult { ps: advance(ps), matched: true, text: tok.text }
    }
    return MatchResult { ps: ps, matched: false, text: "" }
}

// ── Type expression strings ───────────────────────────────────────
// We represent types as their C type strings for direct codegen.

type TypeResult = { ctype: String, ps: PState }

mapper primKindToCtype(kind: Integer) -> String {
    if kind == 260 { return "xc_number_t" }
    if kind == 261 { return "xc_integer_t" }
    if kind == 262 { return "xc_bool_t" }
    if kind == 263 { return "xc_string_t" }
    if kind == 264 { return "xc_char_t" }
    if kind == 265 { return "void" }
    if kind == 266 { return "xc_size_t" }
    if kind == 267 { return "const char*" }
    return ""
}

mapper identToCtype(name: String) -> String {
    return "xc_" + name + "_t"
}

mapper parseTypeExpr(ps: PState) -> TypeResult {
    let t = peek(ps)
    let base = ""
    let ps2 = ps

    // Primitive type keyword
    let pc = primKindToCtype(t.kind)
    if string_len(pc) > 0 {
        base = pc
        ps2 = advance(ps)
    } else {
        // &mut TypeExpr
        if t.kind == 124 {   // &mut
            ps2 = advance(ps)
            let inner = parseTypeExpr(ps2)
            return TypeResult { ctype: inner.ctype + "*", ps: inner.ps }
        }
        // & TypeExpr
        if t.kind == 123 {  // &
            ps2 = advance(ps)
            let inner = parseTypeExpr(ps2)
            return TypeResult { ctype: "const " + inner.ctype + "*", ps: inner.ps }
        }
        // own TypeExpr
        if t.kind == 232 {  // own
            ps2 = advance(ps)
            let inner = parseTypeExpr(ps2)
            return TypeResult { ctype: inner.ctype, ps: inner.ps }
        }
        // Compound type { field: type, ... }
        if t.kind == 102 {  // {
            // anonymous compound — skip for now, return void*
            ps2 = advance(ps)
            let depth = 1
            while depth > 0 {
                let ct = peek(ps2)
                if ct.kind == 102 { depth = depth + 1 }
                if ct.kind == 103 { depth = depth - 1 }
                ps2 = advance(ps2)
            }
            return TypeResult { ctype: "void*", ps: ps2 }
        }
        // Named type
        if t.kind == 1 {  // IDENT
            base = identToCtype(t.text)
            ps2 = advance(ps)
        } else {
            return TypeResult { ctype: "void", ps: ps }
        }
    }

    // Postfix: ? or []
    let finalType = base
    let suf = ctypeSuffix(base)
    let ps3 = ps2
    let continuing = true
    while continuing {
        let pt = peek(ps3)
        if pt.kind == 127 {  // ?  optional
            ps3 = advance(ps3)
            finalType = "xc_opt_" + suf + "_t"
        } else {
            if pt.kind == 126 {  // !  Result-of-T (string error)
                ps3 = advance(ps3)
                finalType = "xc_res_" + suf + "_t"
            } else {
                if pt.kind == 104 and peekAt(ps3, 1).kind == 105 {  // []
                    ps3 = advance(advance(ps3))
                    finalType = "xc_arr_" + suf + "_t"
                } else {
                    continuing = false
                }
            }
        }
    }

    return TypeResult { ctype: finalType, ps: ps3 }
}

// Convert a base C type (e.g. "xc_string_t", "xc_Person_t") to the suffix
// used in xc_arr_<suffix>_t / xc_opt_<suffix>_t typedef names.
mapper ctypeSuffix(ctype: String) -> String {
    if ctype == "xc_number_t"  { return "number" }
    if ctype == "xc_integer_t" { return "integer" }
    if ctype == "xc_bool_t"    { return "bool" }
    if ctype == "xc_string_t"  { return "string" }
    if ctype == "xc_char_t"    { return "char" }
    if ctype == "xc_size_t"    { return "size" }
    if ctype == "xc_timestamp_t" { return "timestamp" }
    // Strip leading "xc_" and trailing "_t"
    let n = string_len(ctype)
    if n > 5 {
        return string_slice(ctype, 3, n - 2)
    }
    return ctype
}

// ── Collected declarations ────────────────────────────────────────

// A field in a compound type or interface
type FieldSpec = { name: String, ctype: String }

// A parameter in a function signature
type ParamSpec = { name: String, ctype: String }

// A function method signature
type MethodSpec = {
    isAsync:   Bool,
    kind:      String,  // "mapper","consumer","predicate","producer","reducer","projector"
    name:      String,
    params:    String,  // comma-separated "ctype name" pairs
    retCtype:  String,
    bodyTokens: Token[]
}

// A type declaration (refined or compound)
type TypeSpec = {
    name:       String,
    isCompound: Bool,
    baseCtype:  String,        // for refined types
    fields:     String[],      // for compound types: "name:ctype" pairs
    hasWhere:   Bool,
    whereSrc:   String,        // (legacy, unused)
    whereTokens: Token[]       // refined-type constraint tokens (no `where`)
}

// An interface
type IfaceSpec = {
    name:     String,
    extendsNames: String[],
    methList: MethodSpec[]
}

// A dep in a class or function.
//   form: "single" | "list" | "or" | "where" | "opt"
type DepSpec = {
    name:       String,
    ctype:      String,
    ifaceName:  String,    // element/interface X name (without xc_ wrapping)
    hasWhen:    Bool,
    form:       String,
    orAlt:      String,    // fallback class for `I or J`
    whereTokens: Token[]   // guard tokens for `I where <cond>`
}

// A class
type ClassSpec = {
    name:       String,
    implNames:  String[],
    depList:    DepSpec[],
    methList:   MethodSpec[]
}

// A module binding
type BindSpec = {
    ifaceName:    String,
    concreteName: String,
    scopeKind:    String
}

// A module
type ModuleSpec = {
    name:     String,
    bindings: BindSpec[]
}

// A top-level function or creator
type FuncSpec = {
    isCreator:   Bool,
    isAsync:     Bool,
    kind:        String,
    name:        String,
    params:      String,    // C param list
    retCtype:    String,
    bodyTokens:  Token[],   // tokens of the body block, excl. outer braces
    hasWhere:    Bool,
    whereTokens: Token[],   // tokens of the overload-selection guard (no braces)
    fnDeps:      DepSpec[] // function-level dependencies:  kind { d: I } name(...)
}

// The whole program
type Program = {
    types:     TypeSpec[],
    ifaces:    IfaceSpec[],
    classes:   ClassSpec[],
    modules:   ModuleSpec[],
    functions: FuncSpec[],
    externs:   FuncSpec[],   // extern "C" signatures (bodyTokens empty)
    entrySpec: FuncSpec      // isCreator=false, kind="entry"
}

// C helpers for building typed arrays used by Program
extern "C" {
    mapper appendFieldSpec(arr: FieldSpec[], s: FieldSpec) -> FieldSpec[]
    mapper appendMethodSpec(arr: MethodSpec[], s: MethodSpec) -> MethodSpec[]
    mapper appendTypeSpec(arr: TypeSpec[], s: TypeSpec) -> TypeSpec[]
    mapper appendIfaceSpec(arr: IfaceSpec[], s: IfaceSpec) -> IfaceSpec[]
    mapper appendDepSpec(arr: DepSpec[], s: DepSpec) -> DepSpec[]
    mapper appendClassSpec(arr: ClassSpec[], s: ClassSpec) -> ClassSpec[]
    mapper appendBindSpec(arr: BindSpec[], s: BindSpec) -> BindSpec[]
    mapper appendModuleSpec(arr: ModuleSpec[], s: ModuleSpec) -> ModuleSpec[]
    mapper appendFuncSpec(arr: FuncSpec[], s: FuncSpec) -> FuncSpec[]

    mapper methodSpecLen(arr: MethodSpec[]) -> Integer
    mapper methodSpecGet(arr: MethodSpec[], i: Integer) -> MethodSpec
    mapper depSpecLen(arr: DepSpec[]) -> Integer
    mapper depSpecGet(arr: DepSpec[], i: Integer) -> DepSpec
    mapper bindSpecLen(arr: BindSpec[]) -> Integer
    mapper bindSpecGet(arr: BindSpec[], i: Integer) -> BindSpec
    mapper typeSpecLen(arr: TypeSpec[]) -> Integer
    mapper typeSpecGet(arr: TypeSpec[], i: Integer) -> TypeSpec
    mapper ifaceSpecLen(arr: IfaceSpec[]) -> Integer
    mapper ifaceSpecGet(arr: IfaceSpec[], i: Integer) -> IfaceSpec
    mapper classSpecLen(arr: ClassSpec[]) -> Integer
    mapper classSpecGet(arr: ClassSpec[], i: Integer) -> ClassSpec
    mapper moduleSpecLen(arr: ModuleSpec[]) -> Integer
    mapper moduleSpecGet(arr: ModuleSpec[], i: Integer) -> ModuleSpec
    mapper funcSpecLen(arr: FuncSpec[]) -> Integer
    mapper funcSpecGet(arr: FuncSpec[], i: Integer) -> FuncSpec
}

// ── Parsing helpers ────────────────────────────────────────────────

// Parse a function kind keyword and return the kind string
type KindResult = { kind: String, ps: PState, ok: Bool }

mapper parseFuncKind(ps: PState) -> KindResult {
    let t = peek(ps)
    if t.kind == 213 { return KindResult { kind: "mapper",    ps: advance(ps), ok: true } }
    if t.kind == 214 { return KindResult { kind: "projector", ps: advance(ps), ok: true } }
    if t.kind == 215 { return KindResult { kind: "predicate", ps: advance(ps), ok: true } }
    if t.kind == 216 { return KindResult { kind: "consumer",  ps: advance(ps), ok: true } }
    if t.kind == 217 { return KindResult { kind: "producer",  ps: advance(ps), ok: true } }
    if t.kind == 218 { return KindResult { kind: "reducer",   ps: advance(ps), ok: true } }
    return KindResult { kind: "", ps: ps, ok: false }
}

// Compute C return type from function kind and declared return type
mapper retCtypeFor(kind: String, declaredRet: String) -> String {
    if kind == "predicate" { return "xc_bool_t" }
    if kind == "consumer"  { return "void" }
    if string_len(declaredRet) > 0 { return declaredRet }
    return "void"
}

// Parse a parameter list (tokens between parens, not including parens)
// Returns "ctype name, ctype name, ..." as a C parameter string
type ParamResult = { params: String, ps: PState }

mapper parseParams(ps: PState) -> ParamResult {
    let parts: String[] = []
    let ps2 = ps
    let running = true
    while running and peek(ps2).kind != 101 and peek(ps2).kind != 0 { // ) or EOF
        // param: name : typeExpr
        let nameTok = peek(ps2)
        if nameTok.kind != 1 {
            // A parameter must start with a name (diag_error exits)
            diag_error(nameTok.line, "expected parameter name, got '" + nameTok.text + "'")
            ps2 = advance(ps2)
        } else {
            ps2 = advance(ps2)  // consume name
            if peek(ps2).kind == 108 { ps2 = advance(ps2) }  // consume :
            let tr = parseTypeExpr(ps2)
            ps2 = tr.ps
            let paramStr = tr.ctype + " " + nameTok.text
            parts = appendString(parts, paramStr)
            // Optional comma
            if peek(ps2).kind == 106 { ps2 = advance(ps2) }  // consume ,
        }
    }
    // Join parts
    let result = ""
    let i = 0
    let plen = stringArrLen(parts)
    while i < plen {
        if i > 0 { result = result + ", " }
        result = result + stringArrGet(parts, i)
        i = i + 1
    }
    return ParamResult { params: result, ps: ps2 }
}

// Parse the return type after ->  (if present)
// Returns empty string if no -> found
type RetResult = { ctype: String, ps: PState }

mapper parseRetType(ps: PState) -> RetResult {
    if peek(ps).kind == 109 {  // ->
        let ps2 = advance(ps)
        let tr = parseTypeExpr(ps2)
        return RetResult { ctype: tr.ctype, ps: tr.ps }
    }
    return RetResult { ctype: "", ps: ps }
}

// Collect all tokens inside a balanced {…} block (excl outer braces)
// Returns the body tokens and state after the closing }
type BodyResult = { bodyTokens: Token[], ps: PState }

mapper parseBody(ps: PState) -> BodyResult {
    let toks: Token[] = []
    if peek(ps).kind != 102 {  // not {
        return BodyResult { bodyTokens: toks, ps: ps }
    }
    let ps2 = advance(ps)  // consume {
    let depth = 1
    while depth > 0 and peek(ps2).kind != 0 {
        let ct = peek(ps2)
        if ct.kind == 102 { depth = depth + 1 }
        if ct.kind == 103 { depth = depth - 1 }
        if depth > 0 { toks = appendToken(toks, ct) }
        ps2 = advance(ps2)
    }
    return BodyResult { bodyTokens: toks, ps: ps2 }
}

// Parse one function/method signature + body → FuncSpec
type FuncResult = { spec: FuncSpec, ps: PState }

mapper parseFunc(ps: PState, isAsync: Bool, isCreator: Bool) -> FuncResult {
    let kindStr = ""
    let ps2 = ps

    if isCreator {
        kindStr = "creator"
        if peek(ps2).kind == 212 { ps2 = advance(ps2) }  // consume "creator"
    } else {
        let kr = parseFuncKind(ps2)
        kindStr = kr.kind
        ps2 = kr.ps
    }

    // optional function-level deps block:  kind { d: I, ... } name(...)
    let fdeps: DepSpec[] = []
    if peek(ps2).kind == 102 {  // {
        ps2 = advance(ps2)
        while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
            let dr = parseDep(ps2)
            fdeps = appendDepSpec(fdeps, dr.spec)
            ps2 = dr.ps
        }
        if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }
    }

    // name
    let nameTok = peek(ps2)
    ps2 = advance(ps2)

    // (params)
    if peek(ps2).kind == 100 { ps2 = advance(ps2) }  // (
    let pr = parseParams(ps2)
    ps2 = pr.ps
    if peek(ps2).kind == 101 { ps2 = advance(ps2) }  // )

    // -> rettype
    let rr = parseRetType(ps2)
    ps2 = rr.ps

    let retCtype = retCtypeFor(kindStr, rr.ctype)

    // optional `where <guard>` before the body
    let hasWhere = false
    let whereTokens: Token[] = []
    if peek(ps2).kind == 242 {  // where
        ps2 = advance(ps2)
        hasWhere = true
        // collect guard tokens until the opening body brace
        while peek(ps2).kind != 102 and peek(ps2).kind != 0 {
            whereTokens = appendToken(whereTokens, peek(ps2))
            ps2 = advance(ps2)
        }
    }

    // body { ... }
    let br = parseBody(ps2)
    ps2 = br.ps

    let spec = FuncSpec {
        isCreator: isCreator,
        isAsync: isAsync,
        kind: kindStr,
        name: nameTok.text,
        params: pr.params,
        retCtype: retCtype,
        bodyTokens: br.bodyTokens,
        hasWhere: hasWhere,
        whereTokens: whereTokens,
        fnDeps: fdeps
    }
    return FuncResult { spec: spec, ps: ps2 }
}

// Parse one method spec from an interface (no body)
type SigResult = { spec: MethodSpec, ps: PState }

mapper parseSig(ps: PState, isAsync: Bool) -> SigResult {
    let kr = parseFuncKind(ps)
    let ps2 = kr.ps
    let nameTok = peek(ps2)
    ps2 = advance(ps2)
    if peek(ps2).kind == 100 { ps2 = advance(ps2) }
    let pr = parseParams(ps2)
    ps2 = pr.ps
    if peek(ps2).kind == 101 { ps2 = advance(ps2) }
    let rr = parseRetType(ps2)
    ps2 = rr.ps
    let retCtype = retCtypeFor(kr.kind, rr.ctype)
    let spec = MethodSpec {
        isAsync: isAsync, kind: kr.kind,
        name: nameTok.text, params: pr.params, retCtype: retCtype,
        bodyTokens: []
    }
    return SigResult { spec: spec, ps: ps2 }
}

// ── Top-level declaration parsers ─────────────────────────────────

// Skip tokens inside a balanced block (depth-tracked with { })
mapper skipBlock(ps: PState) -> PState {
    if peek(ps).kind != 102 { return ps }  // no opening {
    let ps2 = advance(ps)
    let depth = 1
    while depth > 0 and peek(ps2).kind != 0 {
        if peek(ps2).kind == 102 { depth = depth + 1 }
        if peek(ps2).kind == 103 { depth = depth - 1 }
        ps2 = advance(ps2)
    }
    return ps2
}

// Parse `type Name = TypeExpr (where Expr)?`
type TypeResult2 = { spec: TypeSpec, ps: PState }

mapper parseTypeDecl(ps: PState) -> TypeResult2 {
    let ps2 = advance(ps)  // consume "type"
    let name = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 111 { ps2 = advance(ps2) }  // =

    let fields: String[] = []

    // Compound type: { field : type, ... }
    if peek(ps2).kind == 102 {
        ps2 = advance(ps2)  // consume {
        while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
            let fname = peek(ps2).text
            ps2 = advance(ps2)
            if peek(ps2).kind == 108 { ps2 = advance(ps2) }  // :
            let tr = parseTypeExpr(ps2)
            ps2 = tr.ps
            fields = appendString(fields, fname + ":" + tr.ctype)
            if peek(ps2).kind == 106 { ps2 = advance(ps2) }  // ,
        }
        if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }
        let spec = TypeSpec {
            name: name, isCompound: true,
            baseCtype: "", fields: fields,
            hasWhere: false, whereSrc: "", whereTokens: []
        }
        return TypeResult2 { spec: spec, ps: ps2 }
    }

    // Refined type: BaseType (where expr)?
    let tr = parseTypeExpr(ps2)
    ps2 = tr.ps
    let hasWhere = false
    let whereTokens: Token[] = []
    if peek(ps2).kind == 242 {  // where
        hasWhere = true
        ps2 = advance(ps2)
        // collect tokens until the next top-level declaration starts
        while peek(ps2).kind != 0 and not isDeclStart(peek(ps2)) {
            whereTokens = appendToken(whereTokens, peek(ps2))
            ps2 = advance(ps2)
        }
    }
    let spec = TypeSpec {
        name: name, isCompound: false,
        baseCtype: tr.ctype, fields: fields,
        hasWhere: hasWhere, whereSrc: "", whereTokens: whereTokens
    }
    return TypeResult2 { spec: spec, ps: ps2 }
}

predicate isDeclStart(tok: Token) {
    let k = tok.kind
    if k == 200 { return true }  // type
    if k == 201 { return true }  // interface
    if k == 202 { return true }  // class
    if k == 210 { return true }  // module
    if k == 219 { return true }  // entry
    if k == 212 { return true }  // creator
    if k == 213 { return true }  // mapper
    if k == 214 { return true }  // projector
    if k == 215 { return true }  // predicate
    if k == 216 { return true }  // consumer
    if k == 217 { return true }  // producer
    if k == 218 { return true }  // reducer
    if k == 230 { return true }  // async
    if k == 235 { return true }  // extern
    if k == 245 { return true }  // export
    return false
}

// Parse `interface Name (extends A, B)? { methods... }`
type IfaceResult = { spec: IfaceSpec, ps: PState }

mapper parseIface(ps: PState) -> IfaceResult {
    let ps2 = advance(ps)  // consume "interface"
    let name = peek(ps2).text
    ps2 = advance(ps2)

    let exNames: String[] = []
    if peek(ps2).kind == 204 {  // extends
        ps2 = advance(ps2)
        let running = true
        while running and peek(ps2).kind == 1 {
            exNames = appendString(exNames, peek(ps2).text)
            ps2 = advance(ps2)
            if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { running = false }
        }
    }

    let methList: MethodSpec[] = []
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }  // {
    while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
        let isAsync = false
        if peek(ps2).kind == 230 {
            isAsync = true
            ps2 = advance(ps2)
        }
        let kr = parseFuncKind(ps2)
        if kr.ok {
            let sr = parseSig(ps2, isAsync)
            methList = appendMethodSpec(methList, sr.spec)
            ps2 = sr.ps
        } else {
            ps2 = advance(ps2)  // skip unknown
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }

    let spec = IfaceSpec { name: name, extendsNames: exNames, methList: methList }
    return IfaceResult { spec: spec, ps: ps2 }
}

// Parse one dependency:  name: Type [ [] | ? | where <cond> | or Alt ]
type DepResult = { spec: DepSpec, ps: PState }

mapper parseDep(ps: PState) -> DepResult {
    let ps2 = ps
    let dname = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 108 { ps2 = advance(ps2) }  // :
    let dtTok = peek(ps2)
    let ifName = ""
    if dtTok.kind == 1 { ifName = dtTok.text }
    let tr = parseTypeExpr(ps2)
    ps2 = tr.ps

    let form = "single"
    if startsWith2(tr.ctype, "xc_arr_") { form = "list" }
    if startsWith2(tr.ctype, "xc_opt_") { form = "opt" }

    let orAlt = ""
    let whereToks: Token[] = []
    if peek(ps2).kind == 242 {        // where <cond>
        form = "where"
        ps2 = advance(ps2)
        let collecting = true
        while collecting and peek(ps2).kind != 0 {
            let k = peek(ps2).kind
            let nextDep = false
            if k == 1 and peekAt(ps2, 1).kind == 108 { nextDep = true }  // IDENT ':'
            if k == 103 or k == 106 or nextDep {
                collecting = false
            } else {
                whereToks = appendToken(whereToks, peek(ps2))
                ps2 = advance(ps2)
            }
        }
    } else {
        if peek(ps2).kind == 226 {    // or <Alt>
            form = "or"
            ps2 = advance(ps2)
            orAlt = peek(ps2).text
            ps2 = advance(ps2)
        } else {
            if peek(ps2).kind == 206 { // legacy `when { ... }` — ignored (auto/bind)
                ps2 = advance(ps2)
                ps2 = skipBlock(ps2)
            }
        }
    }
    if peek(ps2).kind == 106 { ps2 = advance(ps2) }  // optional ,

    let spec = DepSpec {
        name: dname, ctype: tr.ctype, ifaceName: ifName, hasWhen: false,
        form: form, orAlt: orAlt, whereTokens: whereToks
    }
    return DepResult { spec: spec, ps: ps2 }
}

// Parse `class Name implements A, B { deps { ... } methods... }`
type ClassResult = { spec: ClassSpec, ps: PState }

mapper parseClass(ps: PState) -> ClassResult {
    let ps2 = advance(ps)   // "class"
    let name = peek(ps2).text
    ps2 = advance(ps2)

    // implements
    let implNames: String[] = []
    if peek(ps2).kind == 203 {  // implements
        ps2 = advance(ps2)
        let running = true
        while running and peek(ps2).kind == 1 {
            implNames = appendString(implNames, peek(ps2).text)
            ps2 = advance(ps2)
            if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { running = false }
        }
    }

    if peek(ps2).kind == 102 { ps2 = advance(ps2) }  // {

    // deps block
    let depList: DepSpec[] = []
    if peek(ps2).kind == 205 {  // deps
        ps2 = advance(ps2)
        if peek(ps2).kind == 102 { ps2 = advance(ps2) }  // {
        while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
            let dr = parseDep(ps2)
            depList = appendDepSpec(depList, dr.spec)
            ps2 = dr.ps
        }
        if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }
    }

    // methods and creators
    let methList: MethodSpec[] = []
    while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
        let isAsync = false
        if peek(ps2).kind == 230 {
            isAsync = true
            ps2 = advance(ps2)
        }
        // creator
        if peek(ps2).kind == 212 {
            let fr = parseFunc(ps2, isAsync, true)
            ps2 = fr.ps
            let ms = MethodSpec {
                isAsync: isAsync, kind: "creator",
                name: fr.spec.name, params: fr.spec.params,
                retCtype: fr.spec.retCtype, bodyTokens: fr.spec.bodyTokens
            }
            methList = appendMethodSpec(methList, ms)
        } else {
            let kr = parseFuncKind(ps2)
            if kr.ok {
                let fr = parseFunc(ps2, isAsync, false)
                ps2 = fr.ps
                let ms = MethodSpec {
                    isAsync: isAsync, kind: fr.spec.kind,
                    name: fr.spec.name, params: fr.spec.params,
                    retCtype: fr.spec.retCtype, bodyTokens: fr.spec.bodyTokens
                }
                methList = appendMethodSpec(methList, ms)
            } else {
                ps2 = advance(ps2)
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }

    let spec = ClassSpec { name: name, implNames: implNames, depList: depList, methList: methList }
    return ClassResult { spec: spec, ps: ps2 }
}

// Parse `module Name { bind ... }`
type ModuleResult = { spec: ModuleSpec, ps: PState }

mapper parseModule(ps: PState) -> ModuleResult {
    let ps2 = advance(ps)  // "module"
    let name = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }  // {

    let bindings: BindSpec[] = []
    while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
        // import or bind
        if peek(ps2).kind == 244 {  // import
            ps2 = advance(ps2)
            ps2 = advance(ps2)  // skip module name
        } else {
            if peek(ps2).kind == 208 {  // bind
                ps2 = advance(ps2)
                // interface type name
                let ifName = peek(ps2).text
                let tr = parseTypeExpr(ps2)
                ps2 = tr.ps
                if peek(ps2).kind == 109 { ps2 = advance(ps2) }  // ->
                // binding target
                if peek(ps2).kind == 254 {  // none
                    ps2 = advance(ps2)
                } else {
                    if peek(ps2).kind == 104 {  // [list]
                        ps2 = skipBlock(ps2)
                    } else {
                        let concName = peek(ps2).text
                        ps2 = advance(ps2)
                        let scopeVal = "transient"
                        if peek(ps2).kind == 209 {  // as
                            ps2 = advance(ps2)
                            let scopeTok = peek(ps2)
                            if scopeTok.kind == 239 { scopeVal = "singleton" }
                            if scopeTok.kind == 240 { scopeVal = "transient" }
                            if scopeTok.kind == 241 { scopeVal = "scoped" }
                            ps2 = advance(ps2)
                        }
                        bindings = appendBindSpec(bindings, BindSpec {
                            ifaceName: ifName, concreteName: concName, scopeKind: scopeVal
                        })
                    }
                }
            } else {
                ps2 = advance(ps2)
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }

    let spec = ModuleSpec { name: name, bindings: bindings }
    return ModuleResult { spec: spec, ps: ps2 }
}

// ── Program parser ────────────────────────────────────────────────

creator parseProgram(tokens: Token[]) -> Program {
    let ps = mkPState(tokens)

    let types: TypeSpec[] = []
    let ifaces: IfaceSpec[] = []
    let classes: ClassSpec[] = []
    let modules: ModuleSpec[] = []
    let functions: FuncSpec[] = []
    let externs: FuncSpec[] = []
    let entrySpec = FuncSpec {
        isCreator: false, isAsync: false,
        kind: "entry", name: "main",
        params: "xc_arr_string_t args",
        retCtype: "xc_integer_t",
        bodyTokens: [], hasWhere: false, whereTokens: [], fnDeps: []
    }

    let running = true
    while running and peek(ps).kind != 0 {
        let t = peek(ps)

        // extern "C" { sig* } — collect signatures so we can emit C externs
        if t.kind == 235 {  // extern
            ps = advance(ps)
            if peek(ps).kind == 4 { ps = advance(ps) }   // string "C"
            if peek(ps).kind == 102 { ps = advance(ps) } // {
            while peek(ps).kind != 103 and peek(ps).kind != 0 {
                let isA = false
                if peek(ps).kind == 230 {
                    isA = true
                    ps = advance(ps)
                }
                let kr = parseFuncKind(ps)
                if kr.ok {
                    let nameTok = peek(kr.ps)
                    let ps3 = advance(kr.ps)
                    if peek(ps3).kind == 100 { ps3 = advance(ps3) }
                    let pr = parseParams(ps3)
                    ps3 = pr.ps
                    if peek(ps3).kind == 101 { ps3 = advance(ps3) }
                    let rr = parseRetType(ps3)
                    ps3 = rr.ps
                    let ec = FuncSpec {
                        isCreator: false, isAsync: isA, kind: kr.kind,
                        name: nameTok.text, params: pr.params,
                        retCtype: retCtypeFor(kr.kind, rr.ctype), bodyTokens: [],
                        hasWhere: false, whereTokens: [], fnDeps: []
                    }
                    externs = appendFuncSpec(externs, ec)
                    ps = ps3
                } else {
                    ps = advance(ps)
                }
            }
            if peek(ps).kind == 103 { ps = advance(ps) } // }
        } else {
            // type declaration
            if t.kind == 200 {
                let r = parseTypeDecl(ps)
                types = appendTypeSpec(types, r.spec)
                ps = r.ps
            } else {
                // interface
                if t.kind == 201 {
                    let r = parseIface(ps)
                    ifaces = appendIfaceSpec(ifaces, r.spec)
                    ps = r.ps
                } else {
                    // class
                    if t.kind == 202 {
                        let r = parseClass(ps)
                        classes = appendClassSpec(classes, r.spec)
                        ps = r.ps
                    } else {
                        // module
                        if t.kind == 210 {
                            let r = parseModule(ps)
                            modules = appendModuleSpec(modules, r.spec)
                            ps = r.ps
                        } else {
                            // async prefix
                            let isAsync = false
                            if t.kind == 230 {
                                isAsync = true
                                ps = advance(ps)
                            }

                            // entry
                            if peek(ps).kind == 219 {
                                ps = advance(ps)  // entry keyword
                                let nameTok = peek(ps)
                                ps = advance(ps)
                                if peek(ps).kind == 100 { ps = advance(ps) }
                                let pr = parseParams(ps)
                                ps = pr.ps
                                if peek(ps).kind == 101 { ps = advance(ps) }
                                let rr = parseRetType(ps)
                                ps = rr.ps
                                let br = parseBody(ps)
                                ps = br.ps
                                entrySpec = FuncSpec {
                                    isCreator: false, isAsync: isAsync,
                                    kind: "entry", name: nameTok.text,
                                    params: pr.params,
                                    retCtype: retCtypeFor("entry", rr.ctype),
                                    bodyTokens: br.bodyTokens,
                                    hasWhere: false, whereTokens: [], fnDeps: []
                                }
                            } else {
                                // creator or function kind
                                if peek(ps).kind == 212 {
                                    let fr = parseFunc(ps, isAsync, true)
                                    functions = appendFuncSpec(functions, fr.spec)
                                    ps = fr.ps
                                } else {
                                    if parseFuncKindCheck(ps) {
                                        let fr = parseFunc(ps, isAsync, false)
                                        functions = appendFuncSpec(functions, fr.spec)
                                        ps = fr.ps
                                    } else {
                                        ps = advance(ps)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return Program {
        types: types, ifaces: ifaces, classes: classes,
        modules: modules, functions: functions, externs: externs,
        entrySpec: entrySpec
    }
}

predicate parseFuncKindCheck(ps: PState) {
    let k = peek(ps).kind
    if k == 213 { return true }
    if k == 214 { return true }
    if k == 215 { return true }
    if k == 216 { return true }
    if k == 217 { return true }
    if k == 218 { return true }
    return false
}

