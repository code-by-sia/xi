// Parser — stage 2 contract: tokens -> Program (spec structs).
// Implemented by XiParser (xi_parser.xi); the grammar lives in grammar.xi.
interface Parser {
    mapper parse(toks: Token[]) -> Program
}
