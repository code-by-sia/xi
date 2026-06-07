// xc parser — token stream -> Program (spec structs)
// ── Parser state ─────────────────────────────────────────────────
// The parser is functional: each parse function takes (tokens, pos)
// and returns a result struct with the new position.

type PState = { tokens: Token[], pos: Integer }

creator mkPState(tokens: Token[]) -> PState => PState { tokens: tokens, pos: 0 }

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
mapper advance(ps: PState) -> PState => PState { tokens: ps.tokens, pos: ps.pos + 1 }

// Check current token kind
predicate check(ps: PState, kind: Integer) => peek(ps).kind == kind

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
    match kind {
        260 -> "xc_number_t"
        261 -> "xc_integer_t"
        262 -> "xc_bool_t"
        263 -> "xc_string_t"
        264 -> "xc_char_t"
        265 -> "void"
        266 -> "xc_size_t"
        267 -> "const char*"
        268 -> "xc_bytes_t"
        _   -> ""
    }
}

mapper identToCtype(name: String) -> String => "xc_" + name + "_t"

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
            if t.text == "List" and peekAt(ps, 1).kind == 114 {  // List<T>
                let ep = advance(advance(ps))                    // past `List` and `<`
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_List_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Set" and peekAt(ps, 1).kind == 114 {   // Set<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Set_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Map" and peekAt(ps, 1).kind == 114 {   // Map<K, V>
                let kp = advance(advance(ps))                    // past `Map` and `<`
                let kt = parseTypeExpr(kp)
                let psA = kt.ps
                if peek(psA).kind == 106 { psA = advance(psA) }  // `,`
                let vt = parseTypeExpr(psA)
                ps2 = vt.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Map_" + ctypeSuffix(kt.ctype) + "_" + ctypeSuffix(vt.ctype) + "_t"
            } else {
                base = identToCtype(t.text)
                ps2 = advance(ps)
            } } }
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
    match ctype {
        "xc_number_t"    -> "number"
        "xc_integer_t"   -> "integer"
        "xc_bool_t"      -> "bool"
        "xc_string_t"    -> "string"
        "xc_char_t"      -> "char"
        "xc_size_t"      -> "size"
        "xc_timestamp_t" -> "timestamp"
        _ -> {
            // otherwise strip leading "xc_" and trailing "_t"
            if string_len(ctype) > 5 { return string_slice(ctype, 3, string_len(ctype) - 2) }
            return ctype
        }
    }
}

// ── Collected declarations ────────────────────────────────────────

// A field in a compound type or interface
type FieldSpec = { name: String, ctype: String }

// A parameter in a function signature
type ParamSpec = { name: String, ctype: String }

// A function method signature
type MethodSpec = {
    isAsync:   Bool,
    kind:      String,  // "mapper",...,"listener","action"
    name:      String,
    params:    String,  // comma-separated "ctype name" pairs
    retCtype:  String,
    bodyTokens: Token[],
    topic:     String,  // for `listener` methods: the subscribed topic ("" otherwise)
    hasWhere:  Bool,    // `where`-guarded overload (routing / dispatch by guard)
    whereTokens: Token[],
    fnDeps:    DepSpec[] // method-level dependencies: kind (d: I) name(...)
}

// A type declaration (refined or compound)
type TypeSpec = {
    name:       String,
    isCompound: Bool,
    baseCtype:  String,        // for refined types
    fields:     String[],      // for compound types: "name:ctype" pairs
    hasWhere:   Bool,
    whereSrc:   String,        // (legacy, unused)
    whereTokens: Token[],      // refined-type constraint tokens (no `where`)
    isSum:      Bool,          // tagged-union (sum / algebraic) type
    variants:   String[]       // for sum types: "Variant|f1:ct1,f2:ct2" per variant
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
    scopeKind:    String,
    configPath:   String    // non-empty for `bind I -> readConfig("file")`
}

// A module — DI container plus optional package metadata.
type ModuleSpec = {
    name:        String,
    bindings:    BindSpec[],
    id:          String,    // binary name (xc uses this if set)
    title:       String,    // the `name = "..."` field (display name)
    description: String,
    version:     String,
    license:     String,
    includes:    String[],  // source globs for this module (default ["./**"])
    excludes:    String[]   // globs to drop (default [])
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
    fnDeps:      DepSpec[], // function-level dependencies:  kind { d: I } name(...)
    topic:       String    // for `listener`: subscribed topic ("" otherwise)
}

// An `atom` (active-state / store): a holder of an immutable state value, with
// `transition`s (reducers) that produce the next value.
type AtomSpec = {
    name:          String,
    stateTypeName: String,     // e.g. "Cart" — the state type (for .current)
    initToks:      Token[],    // tokens of the `initial` expression
    transitions:   FuncSpec[] // transition f(s: T, ...) -> T { body }
}

// One arrow of a machine: name(params) : from(,from)* -> to [where g] [update {..}]
type MachineTransition = {
    name:        String,
    params:      String,      // C param string ("" if none)
    froms:       String,      // comma-joined source states
    toState:     String,
    hasGuard:    Bool,
    guardTokens: Token[],     // boolean over params + `data` (no `where`)
    hasUpdate:   Bool,
    updateTokens: Token[]     // tokens inside `update { field: expr, ... }`
}

// A `machine` (finite state machine): named states, optional machine-wide `data`
// context, and transitions with optional params / `where` guards / `update`.
type MachineSpec = {
    name:        String,
    states:      String[],    // ordered; index = state id
    initial:     String,
    terminals:   String[],
    hasData:     Bool,
    dataFields:  String[],    // "name:ctype" for the data context
    dataInit:    Token[],     // tokens inside `data { name: T = expr, ... }`
    transitions: MachineTransition[]
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
    atoms:      AtomSpec[],   // declared `atom`s
    machines:   MachineSpec[], // declared `machine`s
    eventTypes: String[],     // names of declared `event` types (typed payloads)
    tables:     DecisionTable[], // table-form `decision`s (emitted by codegen)
    tests:      FuncSpec[]     // `test "name" (deps) { ... }` cases (kind="test")
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
    mapper appendMachineSpec(arr: MachineSpec[], s: MachineSpec) -> MachineSpec[]
    mapper machineSpecLen(arr: MachineSpec[]) -> Integer
    mapper machineSpecGet(arr: MachineSpec[], i: Integer) -> MachineSpec
    mapper appendMachineTransition(arr: MachineTransition[], s: MachineTransition) -> MachineTransition[]
    mapper machineTransLen(arr: MachineTransition[]) -> Integer
    mapper machineTransGet(arr: MachineTransition[], i: Integer) -> MachineTransition
    mapper appendDecisionRow(arr: DecisionRow[], s: DecisionRow) -> DecisionRow[]
    mapper decisionRowLen(arr: DecisionRow[]) -> Integer
    mapper decisionRowGet(arr: DecisionRow[], i: Integer) -> DecisionRow
    mapper appendDecisionTable(arr: DecisionTable[], s: DecisionTable) -> DecisionTable[]
    mapper decisionTableLen(arr: DecisionTable[]) -> Integer
    mapper decisionTableGet(arr: DecisionTable[], i: Integer) -> DecisionTable

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
    when peek(ps).kind == 295 => KindResult { kind: "listener",  ps: advance(ps), ok: true }
    when peek(ps).kind == 298 => KindResult { kind: "action",    ps: advance(ps), ok: true }
    else                      => KindResult { kind: "", ps: ps, ok: false }
}

// Compute C return type from function kind and declared return type
decision retCtypeFor(kind: String, declaredRet: String) -> String {
    when kind == "predicate"          => "xc_bool_t"
    when kind == "consumer"           => "void"
    when kind == "listener"           => "void"
    when kind == "action"             => "void"
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

creator mkTok(kind: Integer, text: String, line: Integer) -> Token => Token { kind: kind, text: text, line: line }

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

// ── decision table-form ──────────────────────────────────────────────────
// A grid `decision`: `in` columns become parameters, `out` columns the result
// (a scalar for one out, a synthesized `<Name>Out` record for several), each
// `| cell… => out… |` row a rule, with a hit policy (first / unique / collect
// [+ sum|min|max|count]) and the cell DSL. Table decisions are kept structurally
// (here) and emitted directly by codegen (genDecisionTables).

// One rule: the AND-of-cells condition tokens ([] = always), and the output
// expression tokens (one per out column, separated by `|` (kind 125)).
type DecisionRow = { cond: Token[], outs: Token[] }

type DecisionTable = {
    name:      String,
    params:    String,        // C params from `in`
    policy:    String,        // "first" | "unique" | "collect"
    agg:       String,        // "" | "sum" | "min" | "max" | "count"
    outNames:  String[],      // out column names (record field names when multi)
    outCtypes: String[],      // out column ctypes (parallel)
    retElem:   String,        // one row's value ctype: single out ctype, or xc_<Name>Out_t
    retCtype:  String,        // the decision's C return type (by policy/aggregator)
    isMulti:   Bool,          // more than one out -> record
    rows:      DecisionRow[]
}

// Result of parsing a `decision` body. For table-form, `table` is filled and (for
// multi-out) `outType` carries the synthesized record TypeSpec.
type DecisionResult = {
    bodyTokens: Token[], ps: PState, params: String, retCtype: String, isTable: Bool,
    table: DecisionTable, outType: TypeSpec, hasOutType: Bool
}
type RowResult = { cond: Token[], outs: Token[], ps: PState }

// Build a boolean test for one input cell, with `col` as the implicit subject.
// Returns synthesized tokens ([] = wildcard, contributes no condition).
mapper buildCellCond(colName: String, cell: Token[], line: Integer) -> Token[] {
    let out: Token[] = []
    let n = tokenArrLen(cell)
    if n == 0 { return out }
    let f0 = tokenArrGet(cell, 0)
    if n == 1 and f0.kind == 119 { return out }                 // '-' wildcard
    // comparison op first: col OP rest
    if f0.kind == 112 or f0.kind == 114 or f0.kind == 115 or f0.kind == 116 or f0.kind == 117 {
        out = appendToken(out, mkTok(1, colName, line))
        out = concatTokens(out, cell)
        return out
    }
    // not <test>
    if f0.kind == 227 {
        let rest: Token[] = []
        let k = 1
        while k < n { rest = appendToken(rest, tokenArrGet(cell, k)) k = k + 1 }
        out = appendToken(out, mkTok(227, "not", line))
        out = appendToken(out, mkTok(100, "(", line))
        out = concatTokens(out, buildCellCond(colName, rest, line))
        out = appendToken(out, mkTok(101, ")", line))
        return out
    }
    // [ lo .. hi ]  ->  ( col >= lo and col <= hi )   (inclusive range)
    if f0.kind == 104 {
        // split on the `..` (two consecutive '.') between '[' and ']'
        let lo: Token[] = []
        let hi: Token[] = []
        let inHi = false
        let i = 1
        while i < n {
            let it = tokenArrGet(cell, i)
            if it.kind == 105 { i = n }                                  // ]
            else {
                if it.kind == 134 {                                      // `..` (range token)
                    inHi = true
                    i = i + 1
                } else {
                if it.kind == 107 and i + 1 < n and tokenArrGet(cell, i + 1).kind == 107 {
                    inHi = true                                          // legacy: two `.` tokens
                    i = i + 2
                } else {
                    if inHi { hi = appendToken(hi, it) } else { lo = appendToken(lo, it) }
                    i = i + 1
                }
                }
            }
        }
        out = appendToken(out, mkTok(100, "(", line))
        out = appendToken(out, mkTok(1, colName, line))
        out = appendToken(out, mkTok(117, ">=", line))
        out = concatTokens(out, lo)
        out = appendToken(out, mkTok(225, "and", line))
        out = appendToken(out, mkTok(1, colName, line))
        out = appendToken(out, mkTok(116, "<=", line))
        out = concatTokens(out, hi)
        out = appendToken(out, mkTok(101, ")", line))
        return out
    }
    // in { a, b, ... }  ->  ( col == a or col == b ... )
    if f0.kind == 229 {
        out = appendToken(out, mkTok(100, "(", line))
        let i = 1
        if i < n and tokenArrGet(cell, i).kind == 102 { i = i + 1 }   // {
        let firstItem = true
        while i < n and tokenArrGet(cell, i).kind != 103 {
            let it = tokenArrGet(cell, i)
            if it.kind == 106 { i = i + 1 }                           // ,
            else {
                if not firstItem { out = appendToken(out, mkTok(226, "or", line)) }
                out = appendToken(out, mkTok(1, colName, line))
                out = appendToken(out, mkTok(112, "==", line))
                out = appendToken(out, it)
                firstItem = false
                i = i + 1
            }
        }
        out = appendToken(out, mkTok(101, ")", line))
        return out
    }
    // ?( expr )  -> the inner expression verbatim (escape hatch)
    if f0.kind == 127 {
        let i = 1
        if i < n and tokenArrGet(cell, i).kind == 100 { i = i + 1 }   // (
        while i < n and tokenArrGet(cell, i).kind != 101 {
            out = appendToken(out, tokenArrGet(cell, i))
            i = i + 1
        }
        return out
    }
    // bare literal/ident  ->  col == <cell>
    out = appendToken(out, mkTok(1, colName, line))
    out = appendToken(out, mkTok(112, "==", line))
    out = concatTokens(out, cell)
    return out
}

// Parse one `| c1 | c2 => out |` row into an if/return (or a default return).
// Parse one rule: AND-of-cells condition tokens, then `outCount` output exprs
// (kept with `|` separators between them so codegen can split).
mapper parseDecisionRow(ps: PState, inNames: String[], outCount: Integer) -> RowResult {
    let ps2 = ps
    let line = peek(ps2).line
    if peek(ps2).kind == 125 { ps2 = advance(ps2) }       // leading |
    let cond: Token[] = []
    let condStarted = false
    let ci = 0
    let nCols = stringArrLen(inNames)
    let collecting = true
    while collecting {
        let cell: Token[] = []
        let d = 0
        let cellDone = false
        while not cellDone {
            let c = peek(ps2)
            if c.kind == 0 { cellDone = true collecting = false }
            else {
                if d == 0 and (c.kind == 125 or c.kind == 110) { cellDone = true }
                else {
                    if c.kind == 100 or c.kind == 104 or c.kind == 102 { d = d + 1 }
                    if c.kind == 101 or c.kind == 105 or c.kind == 103 { d = d - 1 }
                    cell = appendToken(cell, c)
                    ps2 = advance(ps2)
                }
            }
        }
        if ci < nCols {
            let cc = buildCellCond(stringArrGet(inNames, ci), cell, line)
            if tokenArrLen(cc) > 0 {
                if condStarted { cond = appendToken(cond, mkTok(225, "and", line)) }
                cond = appendToken(cond, mkTok(100, "(", line))
                cond = concatTokens(cond, cc)
                cond = appendToken(cond, mkTok(101, ")", line))
                condStarted = true
            }
        }
        ci = ci + 1
        if peek(ps2).kind == 125 { ps2 = advance(ps2) }                 // | -> next cell
        else { if peek(ps2).kind == 110 { ps2 = advance(ps2) collecting = false }  // =>
               else { collecting = false } }
    }
    // outputs: outCount expressions, recorded with `|` separators between them
    let outs: Token[] = []
    let oi = 0
    while oi < outCount {
        if oi > 0 { outs = appendToken(outs, mkTok(125, "|", line)) }
        let d2 = 0
        let od = false
        while not od {
            let c = peek(ps2)
            if c.kind == 0 or c.kind == 103 { od = true }
            else {
                if d2 == 0 and c.kind == 125 { od = true }
                else {
                    if c.kind == 100 or c.kind == 104 or c.kind == 102 { d2 = d2 + 1 }
                    if c.kind == 101 or c.kind == 105 or c.kind == 103 { d2 = d2 - 1 }
                    outs = appendToken(outs, c)
                    ps2 = advance(ps2)
                }
            }
        }
        oi = oi + 1
        if peek(ps2).kind == 125 { ps2 = advance(ps2) }   // consume separator / trailing |
    }
    return RowResult { cond: cond, outs: outs, ps: ps2 }
}

// Dispatch a `decision` body: table-form (in/out grid) or the shipped when-form.
mapper parseDecision(name: String, ps: PState) -> DecisionResult {
    let emptyToks: Token[] = []
    let emptyStrs: String[] = []
    let emptyRows: DecisionRow[] = []
    let emptyTable = DecisionTable { name: "", params: "", policy: "first", agg: "", outNames: emptyStrs, outCtypes: emptyStrs, retElem: "", retCtype: "", isMulti: false, rows: emptyRows }
    let emptyType = TypeSpec { name: "", isCompound: false, baseCtype: "", fields: emptyStrs, hasWhere: false, whereSrc: "", whereTokens: emptyToks, isSum: false, variants: [] }
    // probe past `{` and an optional `hit <policy>` to detect the form
    let probe = 1
    if peekAt(ps, probe).kind == 257 { probe = probe + 2 }
    let det = peekAt(ps, probe)
    let isTable = det.kind == 229 or (det.kind == 1 and det.text == "out")
    if not isTable {
        let br = parseDecisionBody(ps)
        return DecisionResult { bodyTokens: br.bodyTokens, ps: br.ps, params: "", retCtype: "", isTable: false, table: emptyTable, outType: emptyType, hasOutType: false }
    }
    let ps2 = advance(ps)   // {
    let policy = "first"
    let agg = ""
    if peek(ps2).kind == 257 {                            // hit <policy> [agg]
        ps2 = advance(ps2)
        let pol = peek(ps2)
        if pol.text == "first" or pol.text == "unique" or pol.text == "collect" { policy = pol.text }
        else { diag_error(pol.line, "decision table: unknown hit policy '" + pol.text + "' (use first | unique | collect)") }
        ps2 = advance(ps2)
        if policy == "collect" {
            let a = peek(ps2)
            if a.kind == 1 and (a.text == "sum" or a.text == "min" or a.text == "max" or a.text == "count") {
                agg = a.text
                ps2 = advance(ps2)
            }
        }
    }
    let inNames: String[] = []
    let params = ""
    let outNames: String[] = []
    let outCtypes: String[] = []
    let cols = true
    while cols {
        let t = peek(ps2)
        if t.kind == 257 {                                             // hit <policy> [agg]
            ps2 = advance(ps2)
            let pol = peek(ps2)
            if pol.text == "first" or pol.text == "unique" or pol.text == "collect" { policy = pol.text }
            else { diag_error(pol.line, "decision table: unknown hit policy '" + pol.text + "' (use first | unique | collect)") }
            ps2 = advance(ps2)
            if policy == "collect" {
                let a = peek(ps2)
                if a.kind == 1 and (a.text == "sum" or a.text == "min" or a.text == "max" or a.text == "count") {
                    agg = a.text
                    ps2 = advance(ps2)
                }
            }
        }
        else {
        if t.kind == 229 {                                              // in name : Type
            ps2 = advance(ps2)
            let cn = peek(ps2).text
            ps2 = advance(ps2)
            if peek(ps2).kind == 108 { ps2 = advance(ps2) }
            let tr = parseTypeExpr(ps2)
            ps2 = tr.ps
            inNames = appendString(inNames, cn)
            if string_len(params) > 0 { params = params + ", " }
            params = params + tr.ctype + " " + cn
        } else {
        if t.kind == 1 and t.text == "out" {                            // out name : Type
            ps2 = advance(ps2)
            let on = peek(ps2).text
            ps2 = advance(ps2)
            if peek(ps2).kind == 108 { ps2 = advance(ps2) }
            let tr = parseTypeExpr(ps2)
            ps2 = tr.ps
            outNames = appendString(outNames, on)
            outCtypes = appendString(outCtypes, tr.ctype)
        } else { cols = false }
        }
        }
    }
    let outCount = stringArrLen(outNames)
    if outCount == 0 { diag_error(peek(ps2).line, "decision table: needs at least one 'out' column") }
    let isMulti = outCount > 1
    if isMulti and (agg == "sum" or agg == "min" or agg == "max") {
        diag_error(peek(ps2).line, "decision table: collect " + agg + " needs a single numeric 'out' column")
    }
    let retElem = ""
    let hasOutType = false
    let outType = emptyType
    if isMulti {
        let fields: String[] = []
        let fi = 0
        while fi < outCount {
            fields = appendString(fields, stringArrGet(outNames, fi) + ":" + stringArrGet(outCtypes, fi))
            fi = fi + 1
        }
        outType = TypeSpec { name: name + "Out", isCompound: true, baseCtype: "", fields: fields, hasWhere: false, whereSrc: "", whereTokens: emptyToks, isSum: false, variants: [] }
        hasOutType = true
        retElem = "xc_" + name + "Out_t"
    } else {
        retElem = stringArrGet(outCtypes, 0)
    }
    // function return type: by policy + aggregator
    let retCtype = retElem
    if policy == "collect" {
        if agg == "count" { retCtype = "xc_integer_t" }
        else { if agg == "sum" or agg == "min" or agg == "max" { retCtype = retElem }
               else { retCtype = "xc_arr_" + ctypeSuffix(retElem) + "_t" } }
    }
    // rows
    let rows: DecisionRow[] = []
    let more = true
    while more {
        if peek(ps2).kind == 125 {
            let rr = parseDecisionRow(ps2, inNames, outCount)
            ps2 = rr.ps
            rows = appendDecisionRow(rows, DecisionRow { cond: rr.cond, outs: rr.outs })
        } else { more = false }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }       // }
    let table = DecisionTable {
        name: name, params: params, policy: policy, agg: agg,
        outNames: outNames, outCtypes: outCtypes, retElem: retElem,
        retCtype: retCtype, isMulti: isMulti, rows: rows
    }
    return DecisionResult { bodyTokens: emptyToks, ps: ps2, params: params, retCtype: retCtype, isTable: true, table: table, outType: outType, hasOutType: hasOutType }
}

// Parse one function/method signature + body → FuncSpec
type FuncResult = { spec: FuncSpec, ps: PState, table: DecisionTable, hasTable: Bool, outType: TypeSpec, hasOutType: Bool }

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

    // optional function-level deps block, before the name:
    //   kind { d: I, ... } name(...)   — full form (where / or / list disambiguation)
    //   kind (d: I, ...)  name(...)    — simple form (plain deps, no guards)
    let fdeps: DepSpec[] = []
    if peek(ps2).kind == 102 {  // { ... }
        ps2 = advance(ps2)
        while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
            let dr = parseDep(ps2)
            fdeps = appendDepSpec(fdeps, dr.spec)
            ps2 = dr.ps
        }
        if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }
    } else {
        if peek(ps2).kind == 100 {  // ( ... ) — simple deps
            ps2 = advance(ps2)
            while peek(ps2).kind != 101 and peek(ps2).kind != 0 {
                let dr = parseDep(ps2)
                fdeps = appendDepSpec(fdeps, dr.spec)
                ps2 = dr.ps
            }
            if peek(ps2).kind == 101 { ps2 = advance(ps2) }  // )
        }
    }

    // name
    let nameTok = peek(ps2)
    ps2 = advance(ps2)

    // (params) — table-form decisions have none (columns are declared in the body)
    let pr = ParamResult { params: "", ps: ps2 }
    if peek(ps2).kind == 100 {  // (
        ps2 = advance(ps2)
        pr = parseParams(ps2)
        ps2 = pr.ps
        if peek(ps2).kind == 101 { ps2 = advance(ps2) }  // )
    }

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

    // `listener` subscription clause:  on "topic.name"
    let topic = ""
    if kindStr == "listener" {
        if peek(ps2).kind == 1 and peek(ps2).text == "on" {
            ps2 = advance(ps2)
            if peek(ps2).kind == 4 {   // string literal
                topic = peek(ps2).text
                ps2 = advance(ps2)
            }
        }
    }

    // optional `where <guard>` before the body
    let hasWhere = false
    let whereTokens: Token[] = []
    if peek(ps2).kind == 242 {  // where
        ps2 = advance(ps2)
        hasWhere = true
        // collect guard tokens until the body: a `{` block or an `=>` inline body
        while peek(ps2).kind != 102 and peek(ps2).kind != 110 and peek(ps2).kind != 0 {
            whereTokens = appendToken(whereTokens, peek(ps2))
            ps2 = advance(ps2)
        }
    }

    // body { ... }  (decisions: when-form desugars to if/return tokens; table-form
    // is kept structurally and emitted directly by codegen)
    let emptyStrs0: String[] = []
    let emptyToks0: Token[] = []
    let emptyRows0: DecisionRow[] = []
    let dTable = DecisionTable { name: "", params: "", policy: "first", agg: "", outNames: emptyStrs0, outCtypes: emptyStrs0, retElem: "", retCtype: "", isMulti: false, rows: emptyRows0 }
    let dOutType = TypeSpec { name: "", isCompound: false, baseCtype: "", fields: emptyStrs0, hasWhere: false, whereSrc: "", whereTokens: emptyToks0, isSum: false, variants: [] }
    let hasTable = false
    let hasOutType = false
    let br = parseBody(ps2)
    // Inline body: `=> expr` (single line) is sugar for `{ return expr }`.
    if kindStr != "decision" and peek(ps2).kind == 110 {
        let ips = advance(ps2)                 // consume =>
        let ln0 = peek(ips).line
        let bt: Token[] = []
        bt = appendToken(bt, mkTok(221, "return", ln0))
        while peek(ips).kind != 0 and peek(ips).line == ln0 {
            bt = appendToken(bt, peek(ips))
            ips = advance(ips)
        }
        br = BodyResult { bodyTokens: bt, ps: ips }
    }
    if kindStr == "decision" {
        let dr = parseDecision(nameTok.text, ps2)
        br = BodyResult { bodyTokens: dr.bodyTokens, ps: dr.ps }
        if dr.isTable {
            pr = ParamResult { params: dr.params, ps: pr.ps }   // in-columns become params
            retCtype = dr.retCtype                              // result type by policy/out
            dTable = dr.table
            hasTable = true
            dOutType = dr.outType
            hasOutType = dr.hasOutType
        }
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
        fnDeps: fdeps,
        topic: topic
    }
    return FuncResult { spec: spec, ps: ps2, table: dTable, hasTable: hasTable, outType: dOutType, hasOutType: hasOutType }
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
        bodyTokens: [], topic: "", hasWhere: false, whereTokens: [], fnDeps: []
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
            hasWhere: false, whereSrc: "", whereTokens: [],
            isSum: false, variants: []
        }
        return TypeResult2 { spec: spec, ps: ps2 }
    }

    // Sum / algebraic type:  = | Variant { fields } | Variant2 | ...
    if peek(ps2).kind == 125 {   // leading `|`
        let variants: String[] = []
        while peek(ps2).kind == 125 {
            ps2 = advance(ps2)                       // consume `|`
            let vname = peek(ps2).text
            ps2 = advance(ps2)
            let vfields = ""
            if peek(ps2).kind == 102 {               // optional { fields }
                ps2 = advance(ps2)
                let first = true
                while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
                    let fname = peek(ps2).text
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 108 { ps2 = advance(ps2) }  // :
                    let ftr = parseTypeExpr(ps2)
                    ps2 = ftr.ps
                    if not first { vfields = vfields + "," }
                    vfields = vfields + fname + ":" + ftr.ctype
                    first = false
                    if peek(ps2).kind == 106 { ps2 = advance(ps2) }  // ,
                }
                if peek(ps2).kind == 103 { ps2 = advance(ps2) }      // }
            }
            variants = appendString(variants, vname + "|" + vfields)
        }
        let spec = TypeSpec {
            name: name, isCompound: false,
            baseCtype: "", fields: [],
            hasWhere: false, whereSrc: "", whereTokens: [],
            isSum: true, variants: variants
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
        hasWhere: hasWhere, whereSrc: "", whereTokens: whereTokens,
        isSum: false, variants: []
    }
    return TypeResult2 { spec: spec, ps: ps2 }
}

decision isDeclStart(tok: Token) -> Bool {
    when tok.kind == 200 => true   // type
    when tok.kind == 280 => true   // interrupt
    when tok.kind == 288 => true   // atom
    when tok.kind == 289 => true   // state
    when tok.kind == 292 => true   // machine
    when tok.kind == 296 => true   // event
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
            ps2 = sr.ps
            // Optional default implementation: a `{ ... }` body after the
            // signature. Classes that don't override the method use it.
            let ms = sr.spec
            if peek(ps2).kind == 102 {
                let br = parseBody(ps2)
                ms = MethodSpec {
                    isAsync: ms.isAsync, kind: ms.kind, name: ms.name,
                    params: ms.params, retCtype: ms.retCtype,
                    bodyTokens: br.bodyTokens, topic: ms.topic,
                    hasWhere: false, whereTokens: [], fnDeps: ms.fnDeps
                }
                ps2 = br.ps
            }
            methList = appendMethodSpec(methList, ms)
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
                retCtype: fr.spec.retCtype, bodyTokens: fr.spec.bodyTokens,
                topic: "", hasWhere: false, whereTokens: [], fnDeps: fr.spec.fnDeps
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
                    retCtype: fr.spec.retCtype, bodyTokens: fr.spec.bodyTokens,
                    topic: fr.spec.topic,
                    hasWhere: fr.spec.hasWhere, whereTokens: fr.spec.whereTokens,
                    fnDeps: fr.spec.fnDeps
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
    let name = "App"
    if peek(ps2).kind != 102 {        // a name is present (not an anonymous `module {`)
        name = peek(ps2).text
        ps2 = advance(ps2)
    }
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }  // {

    let bindings: BindSpec[] = []
    let mId = ""
    let mTitle = ""
    let mDesc = ""
    let mVer = ""
    let mLic = ""
    let mIncludes: String[] = []    // unset -> file+imports only; set -> glob-gather
    let mExcludes: String[] = []
    while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
        // import, bind, or a metadata field (key = "value")
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
                    if peek(ps2).kind == 1 and peek(ps2).text == "readConfig" and peekAt(ps2, 1).kind == 100 {
                        // bind I -> readConfig("path") — config-backed implementor
                        let cp = ""
                        ps2 = advance(ps2)                                  // readConfig
                        if peek(ps2).kind == 100 { ps2 = advance(ps2) }    // (
                        if peek(ps2).kind == 4 { cp = peek(ps2).text  ps2 = advance(ps2) }
                        if peek(ps2).kind == 101 { ps2 = advance(ps2) }    // )
                        bindings = appendBindSpec(bindings, BindSpec {
                            ifaceName: ifName, concreteName: "", scopeKind: "singleton", configPath: cp
                        })
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
                            ifaceName: ifName, concreteName: concName, scopeKind: scopeVal, configPath: ""
                        })
                    }
                    }
                }
            } else {
                // metadata field:  key = "value"   or   key = ["a", "b"]
                let key = peek(ps2).text
                if peekAt(ps2, 1).kind == 111 and peekAt(ps2, 2).kind == 104 {
                    // list value: includes / excludes
                    let items: String[] = []
                    ps2 = advance(advance(advance(ps2)))     // past key = [
                    while peek(ps2).kind != 105 and peek(ps2).kind != 0 {
                        if peek(ps2).kind == 4 { items = appendString(items, peek(ps2).text) }
                        ps2 = advance(ps2)
                    }
                    if peek(ps2).kind == 105 { ps2 = advance(ps2) }   // ]
                    if key == "includes" { mIncludes = items }
                    if key == "excludes" { mExcludes = items }
                } else {
                if peekAt(ps2, 1).kind == 111 {              // `=` "value"
                    let val = peekAt(ps2, 2).text
                    if key == "id"          { mId = val }
                    if key == "name"        { mTitle = val }
                    if key == "title"       { mTitle = val }
                    if key == "description" { mDesc = val }
                    if key == "version"     { mVer = val }
                    if key == "license"     { mLic = val }
                    ps2 = advance(advance(advance(ps2)))     // key = value
                } else {
                    ps2 = advance(ps2)
                }
                }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }

    let spec = ModuleSpec {
        name: name, bindings: bindings,
        id: mId, title: mTitle, description: mDesc, version: mVer, license: mLic,
        includes: mIncludes, excludes: mExcludes
    }
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
                        hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
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

type MachineResult = { spec: MachineSpec, ps: PState }

// machine Name {
//   states A,B,C   initial A   [terminal X,Y | -]
//   [data { f: T = expr, ... }]
//   ( name[(params)] : From(,From)* -> To  [where <guard>]  [update { f: expr, ... }] )*
// }
mapper parseMachine(ps: PState) -> MachineResult {
    let ps2 = advance(ps)   // 'machine'
    let name = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }   // {

    let states: String[] = []
    let initial = ""
    let terminals: String[] = []
    let hasData = false
    let dataFields: String[] = []
    let dataInit: Token[] = []
    let transitions: MachineTransition[] = []

    let running = true
    while running {
        let t = peek(ps2)
        if t.kind == 103 or t.kind == 0 {
            running = false
        } else {
            if t.kind == 293 {                  // states A, B, C
                ps2 = advance(ps2)
                let more = true
                while more {
                    if peek(ps2).kind == 1 {
                        states = appendString(states, peek(ps2).text)
                        ps2 = advance(ps2)
                        if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { more = false }
                    } else { more = false }
                }
            } else {
            if t.kind == 291 {                  // initial X
                ps2 = advance(ps2)
                initial = peek(ps2).text
                ps2 = advance(ps2)
            } else {
            if t.kind == 294 {                  // terminal X, Y  |  terminal -
                ps2 = advance(ps2)
                if peek(ps2).kind == 119 { ps2 = advance(ps2) }   // '-' = none
                else {
                    let more = true
                    while more {
                        if peek(ps2).kind == 1 {
                            terminals = appendString(terminals, peek(ps2).text)
                            ps2 = advance(ps2)
                            if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { more = false }
                        } else { more = false }
                    }
                }
            } else {
            if t.kind == 1 and t.text == "data" and peekAt(ps2, 1).kind == 102 {
                // data { f: T = expr, ... }  — machine-wide context
                hasData = true
                ps2 = advance(ps2)   // data
                ps2 = advance(ps2)   // {
                while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
                    let fname = peek(ps2).text
                    dataInit = appendToken(dataInit, peek(ps2))   // name
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 108 { ps2 = advance(ps2) }   // :
                    let dtr = parseTypeExpr(ps2)
                    ps2 = dtr.ps
                    dataFields = appendString(dataFields, fname + ":" + dtr.ctype)
                    if peek(ps2).kind == 111 {                        // =
                        dataInit = appendToken(dataInit, peek(ps2))
                        ps2 = advance(ps2)
                    }
                    let depth = 0
                    let coll = true
                    while coll {
                        let it = peek(ps2)
                        if it.kind == 0 { coll = false }
                        else { if depth == 0 and (it.kind == 106 or it.kind == 103) { coll = false }
                        else {
                            if it.kind == 100 or it.kind == 104 or it.kind == 102 { depth = depth + 1 }
                            if it.kind == 101 or it.kind == 105 or it.kind == 103 { depth = depth - 1 }
                            dataInit = appendToken(dataInit, it)
                            ps2 = advance(ps2)
                        } }
                    }
                    if peek(ps2).kind == 106 {                        // ,
                        dataInit = appendToken(dataInit, peek(ps2))
                        ps2 = advance(ps2)
                    }
                }
                if peek(ps2).kind == 103 { ps2 = advance(ps2) }       // }
            } else {
            if t.kind == 1 {                    // transition: name[(params)] : From* -> To
                let tname = t.text
                ps2 = advance(ps2)
                let params = ""
                if peek(ps2).kind == 100 {       // (params)
                    ps2 = advance(ps2)
                    let pr = parseParams(ps2)
                    params = pr.params
                    ps2 = pr.ps
                    if peek(ps2).kind == 101 { ps2 = advance(ps2) }
                }
                if peek(ps2).kind == 108 { ps2 = advance(ps2) }   // :
                let froms = ""
                let more = true
                while more {
                    if peek(ps2).kind == 1 {
                        if string_len(froms) > 0 { froms = froms + "," }
                        froms = froms + peek(ps2).text
                        ps2 = advance(ps2)
                        if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { more = false }
                    } else { more = false }
                }
                if peek(ps2).kind == 109 { ps2 = advance(ps2) }   // ->
                let toState = peek(ps2).text
                ps2 = advance(ps2)
                // optional `where <guard>` (collected to the end of its line)
                let hasGuard = false
                let guardTokens: Token[] = []
                if peek(ps2).kind == 242 {
                    hasGuard = true
                    let wline = peek(ps2).line
                    ps2 = advance(ps2)
                    let gc = true
                    while gc {
                        let gt = peek(ps2)
                        if gt.kind == 0 or gt.kind == 103 or gt.line != wline or gt.text == "update" { gc = false }
                        else { guardTokens = appendToken(guardTokens, gt) ps2 = advance(ps2) }
                    }
                }
                // optional `update { f: expr, ... }`
                let hasUpdate = false
                let updateTokens: Token[] = []
                if peek(ps2).kind == 1 and peek(ps2).text == "update" and peekAt(ps2, 1).kind == 102 {
                    hasUpdate = true
                    ps2 = advance(ps2)   // update
                    ps2 = advance(ps2)   // {
                    let depth = 1
                    while depth > 0 and peek(ps2).kind != 0 {
                        let ut = peek(ps2)
                        if ut.kind == 102 { depth = depth + 1 }
                        if ut.kind == 103 { depth = depth - 1 }
                        if depth > 0 { updateTokens = appendToken(updateTokens, ut) }
                        ps2 = advance(ps2)
                    }
                }
                transitions = appendMachineTransition(transitions, MachineTransition {
                    name: tname, params: params, froms: froms, toState: toState,
                    hasGuard: hasGuard, guardTokens: guardTokens,
                    hasUpdate: hasUpdate, updateTokens: updateTokens
                })
            } else {
                ps2 = advance(ps2)
            }
            }
            }
            }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }   // }

    let spec = MachineSpec {
        name: name, states: states, initial: initial, terminals: terminals,
        hasData: hasData, dataFields: dataFields, dataInit: dataInit,
        transitions: transitions
    }
    return MachineResult { spec: spec, ps: ps2 }
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
    let machines: MachineSpec[] = []
    let eventTypes: String[] = []
    let tables: DecisionTable[] = []
    let tests: FuncSpec[] = []
    let entrySpec = FuncSpec {
        isCreator: false, isAsync: false,
        kind: "entry", name: "main",
        params: "xc_arr_string_t args",
        retCtype: "xc_integer_t",
        bodyTokens: [], hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
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
                        hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
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
            if t.kind == 200 or t.kind == 280 or t.kind == 289 or t.kind == 296 {
                let r = parseTypeDecl(ps)
                types = appendTypeSpec(types, r.spec)
                if t.kind == 280 { interrupts = appendString(interrupts, r.spec.name) }
                if t.kind == 296 { eventTypes = appendString(eventTypes, r.spec.name) }
                ps = r.ps
            } else {
            if t.kind == 288 {                          // atom declaration
                let ar = parseAtom(ps)
                atoms = appendAtomSpec(atoms, ar.spec)
                ps = ar.ps
            } else {
            if t.kind == 292 {                          // machine declaration
                let mr = parseMachine(ps)
                machines = appendMachineSpec(machines, mr.spec)
                // the machine's value type: { __state: Integer [, data: <M>Data] }
                // (build fields on the heap via appendString — literals would dangle).
                let mfields: String[] = []
                mfields = appendString(mfields, "__state:xc_integer_t")
                if mr.spec.hasData {
                    // the data context as a nested struct, so `m.data.field` works.
                    types = appendTypeSpec(types, TypeSpec {
                        name: mr.spec.name + "Data", isCompound: true, baseCtype: "",
                        fields: mr.spec.dataFields,
                        hasWhere: false, whereSrc: "", whereTokens: [],
                        isSum: false, variants: []
                    })
                    mfields = appendString(mfields, "data:xc_" + mr.spec.name + "Data_t")
                }
                types = appendTypeSpec(types, TypeSpec {
                    name: mr.spec.name, isCompound: true, baseCtype: "",
                    fields: mfields,
                    hasWhere: false, whereSrc: "", whereTokens: [],
                    isSum: false, variants: []
                })
                // register the IllegalTransition interrupt once
                let hasIT = false
                let ii = 0
                while ii < stringArrLen(interrupts) {
                    if stringArrGet(interrupts, ii) == "IllegalTransition" { hasIT = true }
                    ii = ii + 1
                }
                if not hasIT {
                    let itfields: String[] = []
                    itfields = appendString(itfields, "from:xc_string_t")
                    itfields = appendString(itfields, "to:xc_string_t")
                    types = appendTypeSpec(types, TypeSpec {
                        name: "IllegalTransition", isCompound: true, baseCtype: "",
                        fields: itfields,
                        hasWhere: false, whereSrc: "", whereTokens: [],
                        isSum: false, variants: []
                    })
                    interrupts = appendString(interrupts, "IllegalTransition")
                }
                ps = mr.ps
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

                            // test "name" (deps?) { body }
                            if peek(ps).kind == 299 {
                                ps = advance(ps)  // test keyword
                                let testName = peek(ps).text   // string label
                                ps = advance(ps)
                                let tdeps: DepSpec[] = []
                                if peek(ps).kind == 100 {      // (deps)
                                    ps = advance(ps)
                                    while peek(ps).kind != 101 and peek(ps).kind != 0 {
                                        let dr = parseDep(ps)
                                        tdeps = appendDepSpec(tdeps, dr.spec)
                                        ps = dr.ps
                                    }
                                    if peek(ps).kind == 101 { ps = advance(ps) }
                                }
                                let tb = parseBody(ps)
                                ps = tb.ps
                                tests = appendFuncSpec(tests, FuncSpec {
                                    isCreator: false, isAsync: isAsync,
                                    kind: "test", name: testName,
                                    params: "", retCtype: "void",
                                    bodyTokens: tb.bodyTokens,
                                    hasWhere: false, whereTokens: [], fnDeps: tdeps, topic: ""
                                })
                            } else {
                            // entry
                            if peek(ps).kind == 219 {
                                ps = advance(ps)  // entry keyword
                                // optional deps block before the name:
                                //   entry { d: I, ... } main(...)   — full form
                                //   entry (d: I, ...)  main(...)    — simple form
                                let edeps: DepSpec[] = []
                                if peek(ps).kind == 102 {
                                    ps = advance(ps)
                                    while peek(ps).kind != 103 and peek(ps).kind != 0 {
                                        let dr = parseDep(ps)
                                        edeps = appendDepSpec(edeps, dr.spec)
                                        ps = dr.ps
                                    }
                                    if peek(ps).kind == 103 { ps = advance(ps) }
                                } else {
                                    if peek(ps).kind == 100 {
                                        ps = advance(ps)
                                        while peek(ps).kind != 101 and peek(ps).kind != 0 {
                                            let dr = parseDep(ps)
                                            edeps = appendDepSpec(edeps, dr.spec)
                                            ps = dr.ps
                                        }
                                        if peek(ps).kind == 101 { ps = advance(ps) }
                                    }
                                }
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
                                    hasWhere: false, whereTokens: [], fnDeps: edeps, topic: ""
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
                                        if fr.hasTable { tables = appendDecisionTable(tables, fr.table) }
                                        if fr.hasOutType { types = appendTypeSpec(types, fr.outType) }
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
        }
    }

    return Program {
        types: types, ifaces: ifaces, classes: classes,
        modules: modules, functions: functions, externs: externs,
        entrySpec: entrySpec, interrupts: interrupts, atoms: atoms,
        machines: machines, eventTypes: eventTypes, tables: tables,
        tests: tests
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

