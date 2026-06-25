// StdText — the default Text: wraps the string/character FFI. The externs are
// declared here, at the top of their implementation; the class methods use them
// (method names differ from the externs, so a bare call hits the free extern).
extern "C" {
    mapper string_char_at(s: String, i: Integer) -> Integer
    mapper string_len(s: String) -> Integer
    mapper string_slice(s: String, from: Integer, to: Integer) -> String
    mapper findChar(s: String, c: Integer) -> Integer
    mapper int_to_string(n: Integer) -> String
    mapper is_alpha(c: Integer) -> Bool
    mapper is_digit(c: Integer) -> Bool
    mapper is_alnum(c: Integer) -> Bool
    mapper is_space_c(c: Integer) -> Bool
}

class StdText implements Text {
    deps {}
    mapper    len(s: String) -> Integer { return string_len(s) }
    mapper    charAt(s: String, i: Integer) -> Integer { return string_char_at(s, i) }
    mapper    slice(s: String, from: Integer, to: Integer) -> String { return string_slice(s, from, to) }
    mapper    indexOf(s: String, c: Integer) -> Integer { return findChar(s, c) }
    mapper    fromInt(n: Integer) -> String { return int_to_string(n) }
    predicate isAlpha(c: Integer) -> Bool { return is_alpha(c) }
    predicate isDigit(c: Integer) -> Bool { return is_digit(c) }
    predicate isAlnum(c: Integer) -> Bool { return is_alnum(c) }
    predicate isSpace(c: Integer) -> Bool { return is_space_c(c) }
}
