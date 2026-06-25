// XiParser — the default Parser: delegates to the `parseProgram` grammar entry
// point (grammar.xi).
class XiParser implements Parser {
    deps {}
    mapper parse(toks: Token[]) -> Program { return parseProgram(toks) }
}
