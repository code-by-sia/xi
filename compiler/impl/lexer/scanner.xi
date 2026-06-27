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


// ── Tokeniser ────────────────────────────────────────────────────

type LexStep = { tok: Token, pos: Integer, line: Integer }

// Append a token to a Token[] (returns a new array)
// Since X arrays are value types we rebuild with one extra slot.
mapper appendToken(arr: Token[], tok: Token) -> Token[] {
    let n = arr.len + 1
    // We rely on the C runtime to handle this via XC_ARRAY_LIT; for
    // bootstrapping we use a helper written inline.
    return appendTokenC(arr, tok)
}

// Escape a raw string (actual chars) into a C string-literal body: backslash,
// quote and control chars become their C escapes. Used for triple-quoted
// strings, whose content holds real newlines/tabs (a regular `"..."` already
// carries source escapes, so it's emitted as-is).
mapper escRawC(s: String) -> String {
    let out = ""
    let n = string_len(s)
    let i = 0
    while i < n {
        let c = string_char_at(s, i)
        if c == 92      { out = out + "\\" + "\\" }     // \  -> \\
        else { if c == 34 { out = out + "\\" + "\"" }   // "  -> \"
        else { if c == 10 { out = out + "\\" + "n" }    // LF -> \n
        else { if c == 9  { out = out + "\\" + "t" }    // TAB-> \t
        else { if c == 13 { out = out + "\\" + "r" }    // CR -> \r
        else { out = out + string_slice(s, i, i + 1) } } } } }
        i = i + 1
    }
    return out
}

// Strip common leading indentation from a triple-quoted string: drop one leading
// newline (so the text can start on the line after `"""`), then remove the least
// indentation shared by all non-blank lines.
mapper stripIndent(s: String) -> String {
    let n = string_len(s)
    let start = 0
    if n > 0 and string_char_at(s, 0) == 10 { start = 1 }   // drop a leading newline
    // minimum leading-space count over non-blank lines
    let minInd = 1000000
    let i = start
    while i < n {
        let ind = 0
        let j = i
        while j < n and string_char_at(s, j) == 32 { ind = ind + 1  j = j + 1 }
        if j < n and string_char_at(s, j) != 10 {       // non-blank line
            if ind < minInd { minInd = ind }
        }
        while i < n and string_char_at(s, i) != 10 { i = i + 1 }
        if i < n { i = i + 1 }
    }
    if minInd == 1000000 { minInd = 0 }
    // re-emit each line with `minInd` leading spaces removed
    let out = ""
    i = start
    while i < n {
        let skipped = 0
        while skipped < minInd and i < n and string_char_at(s, i) == 32 { i = i + 1  skipped = skipped + 1 }
        while i < n and string_char_at(s, i) != 10 { out = out + string_slice(s, i, i + 1)  i = i + 1 }
        if i < n { out = out + string_slice(s, i, i + 1)  i = i + 1 }   // keep the newline
    }
    return out
}
