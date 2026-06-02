// std/text — string utilities.  import "std/text.x"  then  text.trim(s)
namespace text

extern "C" {
    mapper xstd_strlen(s: String) -> Integer
    mapper xstd_char_at(s: String, i: Integer) -> Integer
    mapper xstd_substring(s: String, from: Integer, to: Integer) -> String
    mapper xstd_trim(s: String) -> String
    predicate xstd_starts_with(s: String, p: String) -> Bool
    predicate xstd_ends_with(s: String, p: String) -> Bool
    predicate xstd_contains(s: String, n: String) -> Bool
    mapper xstd_index_of(s: String, n: String) -> Integer
    mapper xstd_to_upper(s: String) -> String
    mapper xstd_to_lower(s: String) -> String
    mapper xstd_repeat(s: String, n: Integer) -> String
    mapper xstd_replace(s: String, a: String, b: String) -> String
}

mapper length(s: String) -> Integer { return xstd_strlen(s) }
mapper charAt(s: String, i: Integer) -> Integer { return xstd_char_at(s, i) }
mapper substring(s: String, from: Integer, to: Integer) -> String {
    return xstd_substring(s, from, to)
}
mapper trim(s: String) -> String { return xstd_trim(s) }
mapper toUpper(s: String) -> String { return xstd_to_upper(s) }
mapper toLower(s: String) -> String { return xstd_to_lower(s) }
predicate startsWith(s: String, p: String) { return xstd_starts_with(s, p) }
predicate endsWith(s: String, p: String) { return xstd_ends_with(s, p) }
predicate contains(s: String, n: String) { return xstd_contains(s, n) }
mapper indexOf(s: String, n: String) -> Integer { return xstd_index_of(s, n) }
mapper repeat(s: String, n: Integer) -> String { return xstd_repeat(s, n) }
mapper replace(s: String, from: String, to: String) -> String {
    return xstd_replace(s, from, to)
}
predicate isEmpty(s: String) { return xstd_strlen(s) == 0 }
