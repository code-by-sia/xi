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

decision primKindToCtype(kind: Integer) -> String {
    when kind == 260 => "xc_number_t"
    when kind == 261 => "xc_integer_t"
    when kind == 262 => "xc_bool_t"
    when kind == 263 => "xc_string_t"
    when kind == 264 => "xc_char_t"
    when kind == 265 => "void"
    when kind == 266 => "xc_size_t"
    when kind == 267 => "const char*"
    when kind == 268 => "xc_bytes_t"
    else             => ""
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

// An `atom` (active-state / store): a holder of an immutable state value, with
// `transition`s (reducers) that produce the next value.
type AtomSpec = {
    name:          String,
    stateTypeName: String,     // e.g. "Cart" — the state type (for .current)
    initToks:      Token[],    // tokens of the `initial` expression
    transitions:   FuncSpec[] // transition f(s: T, ...) -> T { body }
}

// The whole program
type Program = {
    types:      TypeSpec[],
    ifaces:     IfaceSpec[],
    classes:    ClassSpec[],
    modules:    ModuleSpec[],
    functions:  FuncSpec[],
    externs:    FuncSpec[],   // extern "C" signatures (bodyTokens empty)
    entrySpec:  FuncSpec,     // isCreator=false, kind="entry"
    interrupts: String[],     // names of declared `interrupt` types (for type ids)
    atoms:      AtomSpec[]    // declared `atom`s
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
    mapper appendAtomSpec(arr: AtomSpec[], s: AtomSpec) -> AtomSpec[]
    mapper atomSpecLen(arr: AtomSpec[]) -> Integer
    mapper atomSpecGet(arr: AtomSpec[], i: Integer) -> AtomSpec

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

decision parseFuncKind(ps: PState) -> KindResult {
    when peek(ps).kind == 213 => KindResult { kind: "mapper",    ps: advance(ps), ok: true }
    when peek(ps).kind == 214 => KindResult { kind: "projector", ps: advance(ps), ok: true }
    when peek(ps).kind == 215 => KindResult { kind: "predicate", ps: advance(ps), ok: true }
    when peek(ps).kind == 216 => KindResult { kind: "consumer",  ps: advance(ps), ok: true }
    when peek(ps).kind == 217 => KindResult { kind: "producer",  ps: advance(ps), ok: true }
    when peek(ps).kind == 218 => KindResult { kind: "reducer",   ps: advance(ps), ok: true }
    when peek(ps).kind == 256 => KindResult { kind: "decision",  ps: advance(ps), ok: true }
    else                      => KindResult { kind: "", ps: ps, ok: false }
}

// Compute C return type from function kind and declared return type
decision retCtypeFor(kind: String, declaredRet: String) -> String {
    when kind == "predicate"          => "xc_bool_t"
    when kind == "consumer"           => "void"
    when string_len(declaredRet) > 0  => declaredRet
    else                              => "void"
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

creator mkTok(kind: Integer, text: String, line: Integer) -> Token {
    return Token { kind: kind, text: text, line: line }
}

// Decision tables (DxT). Body grammar:
//     { [hit first] (when <expr> => <expr>)* else => <expr> }
// Desugars to ordinary body tokens — an if/return chain — so codegen is reused:
//     if <cond> { return <res> } ...  return <elseRes>
// Conditions and results are full expressions (may call predicates / use deps).
mapper parseDecisionBody(ps: PState) -> BodyResult {
    let out: Token[] = []
    let ps2 = ps
    if peek(ps2).kind != 102 { return BodyResult { bodyTokens: out, ps: ps2 } }  // {
    ps2 = advance(ps2)

    // optional `hit <policy>` (default: first; only first supported for now)
    if peek(ps2).kind == 257 {
        ps2 = advance(ps2)
        let pol = peek(ps2)
        if pol.text != "first" {
            diag_error(pol.line, "decision: only 'hit first' is supported (got '" + pol.text + "')")
        }
        ps2 = advance(ps2)
    }

    let hasElse = false
    let running = true
    while running {
        let t = peek(ps2)
        if t.kind == 103 or t.kind == 0 {
            running = false
        } else {
            if t.kind == 206 {                      // when <cond> => <res>
                if hasElse { diag_error(t.line, "decision: a 'when' after 'else' can never match") }
                ps2 = advance(ps2)
                // condition: collect until top-level `=>`
                let cond: Token[] = []
                let d = 0
                while running {
                    let c = peek(ps2)
                    if c.kind == 0 { diag_error(t.line, "decision: unterminated 'when' (missing =>)") running = false }
                    if d == 0 and c.kind == 110 { ps2 = advance(ps2) running = false } // => consumed
                    else {
                        if c.kind == 100 or c.kind == 104 { d = d + 1 }
                        if c.kind == 101 or c.kind == 105 { d = d - 1 }
                        cond = appendToken(cond, c)
                        ps2 = advance(ps2)
                    }
                }
                running = true
                // result: collect until top-level when / else / otherwise / }
                let res = collectArmResult(ps2)
                ps2 = res.ps
                out = appendToken(out, mkTok(222, "if", t.line))
                out = concatTokens(out, cond)
                out = appendToken(out, mkTok(102, "{", t.line))
                out = appendToken(out, mkTok(221, "return", t.line))
                out = concatTokens(out, res.bodyTokens)
                out = appendToken(out, mkTok(103, "}", t.line))
            } else {
                if t.kind == 223 or t.kind == 207 {  // else / otherwise => <res>
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 110 { ps2 = advance(ps2) }  // =>
                    let res = collectArmResult(ps2)
                    ps2 = res.ps
                    out = appendToken(out, mkTok(221, "return", t.line))
                    out = concatTokens(out, res.bodyTokens)
                    hasElse = true
                } else {
                    diag_error(t.line, "decision: expected 'when' or 'else', got '" + t.text + "'")
                    ps2 = advance(ps2)
                }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }
    if !hasElse { diag_error(peek(ps2).line, "decision requires an 'else' arm (the default outcome)") }
    return BodyResult { bodyTokens: out, ps: ps2 }
}

// Collect a decision arm's result expression: tokens up to a top-level
// `when` / `else` / `otherwise` / `}` (not consumed).
mapper collectArmResult(ps: PState) -> BodyResult {
    let res: Token[] = []
    let ps2 = ps
    let d = 0
    let going = true
    while going {
        let c = peek(ps2)
        if c.kind == 0 { going = false }
        else {
            if d == 0 and (c.kind == 206 or c.kind == 223 or c.kind == 207) { going = false }
            else {
                if d == 0 and c.kind == 103 { going = false }      // closing } of the table
                else {
                    if c.kind == 100 or c.kind == 104 or c.kind == 102 { d = d + 1 }
                    if c.kind == 101 or c.kind == 105 or c.kind == 103 { d = d - 1 }
                    res = appendToken(res, c)
                    ps2 = advance(ps2)
                }
            }
        }
    }
    return BodyResult { bodyTokens: res, ps: ps2 }
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

    // optional `interrupts T, ...` effect annotation (parsed; checking is future)
    if peek(ps2).kind == 281 {
        ps2 = advance(ps2)
        while peek(ps2).kind != 102 and peek(ps2).kind != 242 and peek(ps2).kind != 0 {
            ps2 = advance(ps2)
        }
    }

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

    // body { ... }  (decisions desugar their when/else arms to an if/return chain)
    let br = parseBody(ps2)
    if kindStr == "decision" {
        let dbr = parseDecisionBody(ps2)
        br = dbr
    }
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

decision isDeclStart(tok: Token) -> Bool {
    when tok.kind == 200 => true   // type
    when tok.kind == 280 => true   // interrupt
    when tok.kind == 288 => true   // atom
    when tok.kind == 289 => true   // state
    when tok.kind == 201 => true   // interface
    when tok.kind == 202 => true   // class
    when tok.kind == 210 => true   // module
    when tok.kind == 219 => true   // entry
    when tok.kind == 212 => true   // creator
    when tok.kind == 213 => true   // mapper
    when tok.kind == 214 => true   // projector
    when tok.kind == 215 => true   // predicate
    when tok.kind == 216 => true   // consumer
    when tok.kind == 217 => true   // producer
    when tok.kind == 218 => true   // reducer
    when tok.kind == 256 => true   // decision
    when tok.kind == 230 => true   // async
    when tok.kind == 235 => true   // extern
    when tok.kind == 245 => true   // export
    else                 => false
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

type AtomResult = { spec: AtomSpec, ps: PState }

// atom name { initial <expr>  (transition f(params) -> T { body })* }
mapper parseAtom(ps: PState) -> AtomResult {
    let ps2 = advance(ps)                 // consume 'atom'
    let name = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }   // {

    let initToks: Token[] = []
    let transitions: FuncSpec[] = []
    let running = true
    while running {
        let t = peek(ps2)
        if t.kind == 103 or t.kind == 0 {
            running = false
        } else {
            if t.kind == 291 {            // initial <expr>
                ps2 = advance(ps2)
                let d = 0
                let coll = true
                while coll {
                    let c = peek(ps2)
                    if c.kind == 0 { coll = false }
                    else {
                        if d == 0 and (c.kind == 290 or c.kind == 103) { coll = false }
                        else {
                            if c.kind == 100 or c.kind == 104 or c.kind == 102 { d = d + 1 }
                            if c.kind == 101 or c.kind == 105 or c.kind == 103 { d = d - 1 }
                            initToks = appendToken(initToks, c)
                            ps2 = advance(ps2)
                        }
                    }
                }
            } else {
                if t.kind == 290 {        // transition name(params) -> ret { body }
                    ps2 = advance(ps2)
                    let fnameTok = peek(ps2)
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 100 { ps2 = advance(ps2) }   // (
                    let pr = parseParams(ps2)
                    ps2 = pr.ps
                    if peek(ps2).kind == 101 { ps2 = advance(ps2) }   // )
                    let rr = parseRetType(ps2)
                    ps2 = rr.ps
                    let br = parseBody(ps2)
                    ps2 = br.ps
                    let fs = FuncSpec {
                        isCreator: false, isAsync: false, kind: "mapper",
                        name: name + "__" + fnameTok.text,
                        params: pr.params, retCtype: rr.ctype,
                        bodyTokens: br.bodyTokens,
                        hasWhere: false, whereTokens: [], fnDeps: []
                    }
                    transitions = appendFuncSpec(transitions, fs)
                } else {
                    ps2 = advance(ps2)
                }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }   // }

    let stateTypeName = ""
    if funcSpecLen(transitions) > 0 {
        stateTypeName = ctypeSuffix(funcSpecGet(transitions, 0).retCtype)
    } else {
        if tokenArrLen(initToks) > 0 { stateTypeName = tokenArrGet(initToks, 0).text }
    }
    let spec = AtomSpec {
        name: name, stateTypeName: stateTypeName,
        initToks: initToks, transitions: transitions
    }
    return AtomResult { spec: spec, ps: ps2 }
}

creator parseProgram(tokens: Token[]) -> Program {
    let ps = mkPState(tokens)

    let types: TypeSpec[] = []
    let ifaces: IfaceSpec[] = []
    let classes: ClassSpec[] = []
    let modules: ModuleSpec[] = []
    let functions: FuncSpec[] = []
    let externs: FuncSpec[] = []
    let interrupts: String[] = []
    let atoms: AtomSpec[] = []
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
            // type / interrupt / state declaration. `interrupt` is a compound
            // type that also gets an id; `state` is a compound type (an atom's
            // immutable value type).
            if t.kind == 200 or t.kind == 280 or t.kind == 289 {
                let r = parseTypeDecl(ps)
                types = appendTypeSpec(types, r.spec)
                if t.kind == 280 { interrupts = appendString(interrupts, r.spec.name) }
                ps = r.ps
            } else {
            if t.kind == 288 {                          // atom declaration
                let ar = parseAtom(ps)
                atoms = appendAtomSpec(atoms, ar.spec)
                ps = ar.ps
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
    }

    return Program {
        types: types, ifaces: ifaces, classes: classes,
        modules: modules, functions: functions, externs: externs,
        entrySpec: entrySpec, interrupts: interrupts, atoms: atoms
    }
}

decision parseFuncKindCheck(ps: PState) -> Bool {
    when peek(ps).kind == 213 => true
    when peek(ps).kind == 214 => true
    when peek(ps).kind == 215 => true
    when peek(ps).kind == 216 => true
    when peek(ps).kind == 217 => true
    when peek(ps).kind == 218 => true
    when peek(ps).kind == 256 => true   // decision
    else                      => false
}

