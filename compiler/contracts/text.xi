// Text — string and character primitives. Injectable wrapper over the string
// FFI; implemented by StdText (impl/ffi/text/std_text.xi).
interface Text {
    mapper    len(s: String) -> Integer
    mapper    charAt(s: String, i: Integer) -> Integer
    mapper    slice(s: String, from: Integer, to: Integer) -> String
    mapper    indexOf(s: String, c: Integer) -> Integer
    mapper    fromInt(n: Integer) -> String
    predicate isAlpha(c: Integer) -> Bool
    predicate isDigit(c: Integer) -> Bool
    predicate isAlnum(c: Integer) -> Bool
    predicate isSpace(c: Integer) -> Bool
}
