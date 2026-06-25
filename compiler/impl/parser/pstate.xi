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

