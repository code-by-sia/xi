// ================================================================
// xc — the X language compiler, written in X (lexer module)
//
// This is the self-hosting implementation of xc.
// Pipeline: source file → tokenise → parse → generate C → cc → binary
//
// Build the whole compiler from source:
//   ./compiler/bootstrap.sh
// Compile a program:
//   ./compiler/xc <source.x>        # writes build/<name>
// ================================================================

// ── Extern C helpers ─────────────────────────────────────────────
extern "C" {
    mapper string_char_at(s: String, i: Integer) -> Integer
    mapper string_len(s: String) -> Integer
    mapper string_slice(s: String, from: Integer, to: Integer) -> String
    mapper is_alpha(c: Integer) -> Bool
    mapper is_digit(c: Integer) -> Bool
    mapper is_alnum(c: Integer) -> Bool
    mapper is_space_c(c: Integer) -> Bool
    mapper int_to_string(n: Integer) -> String
    producer file_read_all(path: String) -> String
    producer file_write(path: String, content: String) -> Bool
    consumer diag_error(line: Integer, msg: String)
}

// ── Token kind constants ─────────────────────────────────────────
// Used as Integer discriminants; grouped by range:
//   0       = EOF
//   1..9    = literals
//   10..99  = identifiers / words
//   100..199= punctuation / operators
//   200..499= keywords

type Token = {
    kind:  Integer,
    text:  String,
    line:  Integer
}

// literal kinds
type K_EOF         = Integer   // 0
type K_IDENT       = Integer   // 1
type K_INT_LIT     = Integer   // 2
type K_FLOAT_LIT   = Integer   // 3
type K_STRING_LIT  = Integer   // 4
type K_BOOL_LIT    = Integer   // 5
type K_NONE_LIT    = Integer   // 6

// punctuation / operators
type K_LPAREN  = Integer  // 100
type K_RPAREN  = Integer  // 101
type K_LBRACE  = Integer  // 102
type K_RBRACE  = Integer  // 103
type K_LBRACKET= Integer  // 104
type K_RBRACKET= Integer  // 105
type K_COMMA   = Integer  // 106
type K_DOT     = Integer  // 107
type K_COLON   = Integer  // 108
type K_ARROW   = Integer  // 109  ->
type K_FAT_ARR = Integer  // 110  =>
type K_EQ      = Integer  // 111  =
type K_EQEQ    = Integer  // 112  ==
type K_NEQ     = Integer  // 113  !=
type K_LT      = Integer  // 114
type K_GT      = Integer  // 115
type K_LEQ     = Integer  // 116
type K_GEQ     = Integer  // 117
type K_PLUS    = Integer  // 118
type K_MINUS   = Integer  // 119
type K_STAR    = Integer  // 120
type K_SLASH   = Integer  // 121
type K_PERCENT = Integer  // 122
type K_AMP     = Integer  // 123  &
type K_AMPMUT  = Integer  // 124  &mut
type K_PIPE    = Integer  // 125  |
type K_BANG    = Integer  // 126  !
type K_QUEST   = Integer  // 127  ?
type K_QQ      = Integer  // 128  ??
type K_QDOT    = Integer  // 129  ?.
type K_PLUSE   = Integer  // 130  +=
type K_MINE    = Integer  // 131  -=
type K_STARE   = Integer  // 132  *=
type K_SLASHE  = Integer  // 133  /=
type K_SEMI    = Integer  // 134  ;

// keywords 200+
type K_TYPE      = Integer  // 200
type K_IFACE     = Integer  // 201
type K_CLASS     = Integer  // 202
type K_IMPLEMENTS= Integer  // 203
type K_EXTENDS   = Integer  // 204
type K_DEPS      = Integer  // 205
type K_WHEN      = Integer  // 206
type K_OTHERWISE = Integer  // 207
type K_BIND      = Integer  // 208
type K_AS        = Integer  // 209
type K_MODULE    = Integer  // 210
type K_SCOPE     = Integer  // 211
type K_CREATOR   = Integer  // 212
type K_MAPPER    = Integer  // 213
type K_PROJECTOR = Integer  // 214
type K_PREDICATE = Integer  // 215
type K_CONSUMER  = Integer  // 216
type K_PRODUCER  = Integer  // 217
type K_REDUCER   = Integer  // 218
type K_ENTRY     = Integer  // 219
type K_LET       = Integer  // 220
type K_RETURN    = Integer  // 221
type K_IF        = Integer  // 222
type K_ELSE      = Integer  // 223
type K_MATCH     = Integer  // 224
type K_AND       = Integer  // 225
type K_OR        = Integer  // 226
type K_NOT       = Integer  // 227
type K_IS        = Integer  // 228
type K_IN        = Integer  // 229
type K_ASYNC     = Integer  // 230
type K_AWAIT     = Integer  // 231
type K_OWN       = Integer  // 232
type K_DUP       = Integer  // 233
type K_UNSAFE    = Integer  // 234
type K_EXTERN    = Integer  // 235
type K_TRUE_KW   = Integer  // 236
type K_FALSE_KW  = Integer  // 237
type K_SELF      = Integer  // 238
type K_SINGLETON = Integer  // 239
type K_TRANSIENT = Integer  // 240
type K_SCOPED_KW = Integer  // 241
type K_WHERE     = Integer  // 242
type K_VALUE     = Integer  // 243
type K_IMPORT    = Integer  // 244
type K_EXPORT    = Integer  // 245
type K_FOR       = Integer  // 246
type K_WHILE     = Integer  // 247
type K_LOOP      = Integer  // 248
type K_BREAK     = Integer  // 249
type K_CONTINUE  = Integer  // 250
type K_SPAWN     = Integer  // 251
type K_MATCHES   = Integer  // 252
type K_INPUT     = Integer  // 253
type K_NONE_KW   = Integer  // 254
type K_NUMBER_KW = Integer  // 260
type K_INT_KW    = Integer  // 261
type K_BOOL_KW   = Integer  // 262
type K_STRING_KW = Integer  // 263
type K_CHAR_KW   = Integer  // 264
type K_VOID_KW   = Integer  // 265
type K_SIZE_KW   = Integer  // 266
type K_CSTRING_KW= Integer  // 267

// ── Lexer state ──────────────────────────────────────────────────

type LexState = {
    pos:  Integer,
    line: Integer,
    col:  Integer
}

creator mkLexState() -> LexState {
    return LexState { pos: 0, line: 1, col: 1 }
}

// Map a keyword string to its integer kind (a decision table; default = IDENT).
mapper kwKind(word: String) -> Integer {
    match word {
        "type"        -> 200
        "interface"   -> 201
        "class"       -> 202
        "implements"  -> 203
        "extends"     -> 204
        "deps"        -> 205
        "when"        -> 206
        "otherwise"   -> 207
        "bind"        -> 208
        "as"          -> 209
        "module"      -> 210
        "scope"       -> 211
        "creator"     -> 212
        "mapper"      -> 213
        "projector"   -> 214
        "predicate"   -> 215
        "consumer"    -> 216
        "producer"    -> 217
        "reducer"     -> 218
        "entry"       -> 219
        "let"         -> 220
        "return"      -> 221
        "if"          -> 222
        "else"        -> 223
        "match"       -> 224
        "and"         -> 225
        "or"          -> 226
        "not"         -> 227
        "is"          -> 228
        "in"          -> 229
        "async"       -> 230
        "await"       -> 231
        "own"         -> 232
        "dup"         -> 233
        "unsafe"      -> 234
        "extern"      -> 235
        "true"        -> 236
        "false"       -> 237
        "self"        -> 238
        "singleton"   -> 239
        "transient"   -> 240
        "scoped"      -> 241
        "where"       -> 242
        "value"       -> 243
        "import"      -> 244
        "export"      -> 245
        "for"         -> 246
        "while"       -> 247
        "loop"        -> 248
        "break"       -> 249
        "continue"    -> 250
        "spawn"       -> 251
        "matches"     -> 252
        "input"       -> 253
        "none"        -> 254
        "namespace"   -> 255
        "decision"    -> 256
        "hit"         -> 257
        "interrupt"   -> 280
        "interrupts"  -> 281
        "signal"      -> 282
        "try"         -> 283
        "catch"       -> 284
        "recover"     -> 285
        "skip"        -> 286
        "atom"        -> 288
        "state"       -> 289
        "transition"  -> 290
        "initial"     -> 291
        "machine"     -> 292
        "states"      -> 293
        "terminal"    -> 294
        "listener"    -> 295
        "event"       -> 296
        "action"      -> 298
        "Number"      -> 260
        "Integer"     -> 261
        "Bool"        -> 262
        "String"      -> 263
        "Char"        -> 264
        "Void"        -> 265
        "Size"        -> 266
        "cstring"     -> 267
        "Bytes"       -> 268
        else          -> 1     // IDENT
    }
}

// ── Tokeniser ────────────────────────────────────────────────────

type LexStep = { tok: Token, pos: Integer, line: Integer }

// prevKind = kind of the previously emitted token; used to disambiguate '/'
// (regex literal vs division).  After a value (ident/number/string/`)`/`]`),
// '/' is division; otherwise it begins a regex literal.
mapper lexOne(src: String, pos: Integer, line: Integer, prevKind: Integer) -> LexStep {
    let slen = string_len(src)

    // Skip whitespace and comments
    let p = pos
    let ln = line
    let scanning = true
    while scanning and p < slen {
        let c = string_char_at(src, p)
        if is_space_c(c) {
            if c == 10 { ln = ln + 1 }   // newline = 10
            p = p + 1
        } else {
            if c == 47 and string_char_at(src, p + 1) == 47 {  // //
                p = p + 2
                while p < slen and string_char_at(src, p) != 10 {
                    p = p + 1
                }
            } else {
                if c == 47 and string_char_at(src, p + 1) == 42 {  // /*
                    p = p + 2
                    while p < slen {
                        if string_char_at(src, p) == 10 { ln = ln + 1 }
                        if string_char_at(src, p) == 42 and string_char_at(src, p + 1) == 47 {
                            p = p + 2
                            p = slen  // force exit of while (use dummy value)
                        } else {
                            p = p + 1
                        }
                    }
                } else {
                    scanning = false
                }
            }
        }
    }

    if p >= slen {
        return LexStep { tok: Token { kind: 0, text: "", line: ln }, pos: p, line: ln }
    }

    let ch = string_char_at(src, p)

    // Identifiers and keywords
    if is_alpha(ch) or ch == 95 {   // _ = 95
        let start = p
        while p < slen and (is_alnum(string_char_at(src, p)) or string_char_at(src, p) == 95) {
            p = p + 1
        }
        let word = string_slice(src, start, p)
        let kind = kwKind(word)
        return LexStep { tok: Token { kind: kind, text: word, line: ln }, pos: p, line: ln }
    }

    // Integer and float literals
    if is_digit(ch) {
        let start = p
        let isFloat = false
        // Hex
        if ch == 48 and p + 1 < slen and string_char_at(src, p + 1) == 120 { // 0x
            p = p + 2
            while p < slen and is_alnum(string_char_at(src, p)) { p = p + 1 }
        } else {
            // Binary
            if ch == 48 and p + 1 < slen and string_char_at(src, p + 1) == 98 { // 0b
                p = p + 2
                while p < slen and (string_char_at(src, p) == 48 or string_char_at(src, p) == 49) { p = p + 1 }
            } else {
                while p < slen and is_digit(string_char_at(src, p)) { p = p + 1 }
                if p < slen and string_char_at(src, p) == 46 and p + 1 < slen and is_digit(string_char_at(src, p + 1)) {
                    isFloat = true
                    p = p + 1
                    while p < slen and is_digit(string_char_at(src, p)) { p = p + 1 }
                }
                if p < slen and (string_char_at(src, p) == 101 or string_char_at(src, p) == 69) { // e E
                    isFloat = true
                    p = p + 1
                    if p < slen and (string_char_at(src, p) == 43 or string_char_at(src, p) == 45) { p = p + 1 }
                    while p < slen and is_digit(string_char_at(src, p)) { p = p + 1 }
                }
            }
        }
        let numText = string_slice(src, start, p)
        if isFloat {
            return LexStep { tok: Token { kind: 3, text: numText, line: ln }, pos: p, line: ln }
        } else {
            return LexStep { tok: Token { kind: 2, text: numText, line: ln }, pos: p, line: ln }
        }
    }

    // String literals
    if ch == 34 {   // "
        // Triple-quoted?
        if p + 2 < slen and string_char_at(src, p + 1) == 34 and string_char_at(src, p + 2) == 34 {
            p = p + 3
            let start = p
            while p + 2 < slen {
                if string_char_at(src, p) == 34 and string_char_at(src, p + 1) == 34 and string_char_at(src, p + 2) == 34 {
                    let content = string_slice(src, start, p)
                    p = p + 3
                    return LexStep { tok: Token { kind: 4, text: content, line: ln }, pos: p, line: ln }
                }
                if string_char_at(src, p) == 10 { ln = ln + 1 }
                p = p + 1
            }
        } else {
            p = p + 1  // skip opening "
            let start = p
            while p < slen and string_char_at(src, p) != 34 {
                if string_char_at(src, p) == 92 { p = p + 1 }  // skip escape
                p = p + 1
            }
            let content = string_slice(src, start, p)
            if p < slen { p = p + 1 }  // skip closing "
            return LexStep { tok: Token { kind: 4, text: content, line: ln }, pos: p, line: ln }
        }
    }

    // Regex literals /pattern/  vs  division '/'  (decided by prevKind).
    // Division context: after an ident(1)/int(2)/float(3)/string(4)/`)`(101)/`]`(105).
    if ch == 47 {  // /  (already ruled out //, /*)
        let afterValue = false
        if prevKind == 1   { afterValue = true }
        if prevKind == 2   { afterValue = true }
        if prevKind == 3   { afterValue = true }
        if prevKind == 4   { afterValue = true }
        if prevKind == 101 { afterValue = true }
        if prevKind == 105 { afterValue = true }
        if not afterValue {
            p = p + 1
            let start = p
            while p < slen and string_char_at(src, p) != 47 {
                if string_char_at(src, p) == 92 { p = p + 1 }
                p = p + 1
            }
            let content = string_slice(src, start, p)
            if p < slen { p = p + 1 }
            return LexStep { tok: Token { kind: 4, text: content, line: ln }, pos: p, line: ln }
        }
    }

    // Two-char operators
    if ch == 45 and p + 1 < slen and string_char_at(src, p + 1) == 62 { // ->
        return LexStep { tok: Token { kind: 109, text: "->", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 61 and p + 1 < slen and string_char_at(src, p + 1) == 62 { // =>
        return LexStep { tok: Token { kind: 110, text: "=>", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 61 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // ==
        return LexStep { tok: Token { kind: 112, text: "==", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 33 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // !=
        return LexStep { tok: Token { kind: 113, text: "!=", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 60 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // <=
        return LexStep { tok: Token { kind: 116, text: "<=", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 62 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // >=
        return LexStep { tok: Token { kind: 117, text: ">=", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 38 and p + 1 < slen {  // &mut
        // check for &mut (look ahead for 'm','u','t')
        if string_char_at(src, p + 1) == 109 and p + 3 < slen {
            if string_char_at(src, p + 2) == 117 and string_char_at(src, p + 3) == 116 {
                return LexStep { tok: Token { kind: 124, text: "&mut", line: ln }, pos: p + 4, line: ln }
            }
        }
    }
    if ch == 63 and p + 1 < slen and string_char_at(src, p + 1) == 63 { // ??
        return LexStep { tok: Token { kind: 128, text: "??", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 63 and p + 1 < slen and string_char_at(src, p + 1) == 46 { // ?.
        return LexStep { tok: Token { kind: 129, text: "?.", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 43 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // +=
        return LexStep { tok: Token { kind: 130, text: "+=", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 45 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // -=
        return LexStep { tok: Token { kind: 131, text: "-=", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 42 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // *=
        return LexStep { tok: Token { kind: 132, text: "*=", line: ln }, pos: p + 2, line: ln }
    }
    if ch == 47 and p + 1 < slen and string_char_at(src, p + 1) == 61 { // /=
        return LexStep { tok: Token { kind: 133, text: "/=", line: ln }, pos: p + 2, line: ln }
    }

    // Single-char punctuation
    let singleMap = 100
    if ch == 40  { return LexStep { tok: Token { kind: 100, text: "(", line: ln }, pos: p + 1, line: ln } }
    if ch == 41  { return LexStep { tok: Token { kind: 101, text: ")", line: ln }, pos: p + 1, line: ln } }
    if ch == 123 { return LexStep { tok: Token { kind: 102, text: "{", line: ln }, pos: p + 1, line: ln } }
    if ch == 125 { return LexStep { tok: Token { kind: 103, text: "}", line: ln }, pos: p + 1, line: ln } }
    if ch == 91  { return LexStep { tok: Token { kind: 104, text: "[", line: ln }, pos: p + 1, line: ln } }
    if ch == 93  { return LexStep { tok: Token { kind: 105, text: "]", line: ln }, pos: p + 1, line: ln } }
    if ch == 44  { return LexStep { tok: Token { kind: 106, text: ",", line: ln }, pos: p + 1, line: ln } }
    if ch == 46  { return LexStep { tok: Token { kind: 107, text: ".", line: ln }, pos: p + 1, line: ln } }
    if ch == 58  { return LexStep { tok: Token { kind: 108, text: ":", line: ln }, pos: p + 1, line: ln } }
    if ch == 61  { return LexStep { tok: Token { kind: 111, text: "=", line: ln }, pos: p + 1, line: ln } }
    if ch == 60  { return LexStep { tok: Token { kind: 114, text: "<", line: ln }, pos: p + 1, line: ln } }
    if ch == 62  { return LexStep { tok: Token { kind: 115, text: ">", line: ln }, pos: p + 1, line: ln } }
    if ch == 43  { return LexStep { tok: Token { kind: 118, text: "+", line: ln }, pos: p + 1, line: ln } }
    if ch == 45  { return LexStep { tok: Token { kind: 119, text: "-", line: ln }, pos: p + 1, line: ln } }
    if ch == 42  { return LexStep { tok: Token { kind: 120, text: "*", line: ln }, pos: p + 1, line: ln } }
    if ch == 47  { return LexStep { tok: Token { kind: 121, text: "/", line: ln }, pos: p + 1, line: ln } }
    if ch == 37  { return LexStep { tok: Token { kind: 122, text: "%", line: ln }, pos: p + 1, line: ln } }
    if ch == 38  { return LexStep { tok: Token { kind: 123, text: "&", line: ln }, pos: p + 1, line: ln } }
    if ch == 124 { return LexStep { tok: Token { kind: 125, text: "|", line: ln }, pos: p + 1, line: ln } }
    if ch == 33  { return LexStep { tok: Token { kind: 126, text: "!", line: ln }, pos: p + 1, line: ln } }
    if ch == 63  { return LexStep { tok: Token { kind: 127, text: "?", line: ln }, pos: p + 1, line: ln } }
    if ch == 59  { return LexStep { tok: Token { kind: 134, text: ";", line: ln }, pos: p + 1, line: ln } }

    // Unknown character — report and stop (diag_error exits)
    diag_error(ln, "unexpected character (code " + ch + ")")
    return LexStep { tok: Token { kind: 0, text: "", line: ln }, pos: p + 1, line: ln }
}

creator tokenise(src: String) -> Token[] {
    let slen = string_len(src)
    let tokens: Token[] = []
    let p = 0
    let ln = 1
    let running = true
    let prevKind = 0   // kind of the last emitted token (for / regex-vs-divide)

    while running {
        let step = lexOne(src, p, ln, prevKind)
        p = step.pos
        ln = step.line
        if step.tok.kind == 0 {
            running = false
        } else {
            tokens = appendToken(tokens, step.tok)
            prevKind = step.tok.kind
        }
    }

    // Append EOF
    tokens = appendToken(tokens, Token { kind: 0, text: "", line: ln })
    return tokens
}

// Append a token to a Token[] (returns a new array)
// Since X arrays are value types we rebuild with one extra slot.
mapper appendToken(arr: Token[], tok: Token) -> Token[] {
    let n = arr.len + 1
    // We rely on the C runtime to handle this via XC_ARRAY_LIT; for
    // bootstrapping we use a helper written inline.
    return appendTokenC(arr, tok)
}

// C helper: appends one token to a Token[] reusing / growing the buffer
extern "C" {
    mapper appendTokenC(arr: Token[], tok: Token) -> Token[]
    mapper appendString(arr: String[], s: String) -> String[]
    mapper stringArrLen(arr: String[]) -> Integer
    mapper stringArrGet(arr: String[], i: Integer) -> String
    mapper tokenArrLen(arr: Token[]) -> Integer
    mapper tokenArrGet(arr: Token[], i: Integer) -> Token
}

