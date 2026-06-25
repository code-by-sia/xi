// Lexer — stage 1 contract: source text -> tokens.
// Implemented by XiLexer (xi_lexer.xi); the scanner itself lives in scanner.xi.
interface Lexer {
    mapper lex(src: String) -> Token[]
}
