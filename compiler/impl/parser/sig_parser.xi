// xc parser — signatures: params, return, body, kinds
// (part of the parser — spliced via the xc.xi manifest)

// ── Parsing helpers ────────────────────────────────────────────────

// A binary/prefix operator that still needs a right operand — used to let a
// machine `where` guard continue onto the next line when it ends mid-expression.
predicate expectsOperand(k: Integer) {
    if k == 225 or k == 226 or k == 227 { return true }   // and / or / not
    if k >= 112 and k <= 122 { return true }              // == != < > <= >= + - * / %
    return false
}

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
    when kind == "entry"              => "xc_integer_t"   // entry is always Integer (implicit return 0)
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

