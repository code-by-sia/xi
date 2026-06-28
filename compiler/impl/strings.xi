// xc — shared String predicates.
//
// Single responsibility: small, general-purpose String tests used across the
// lexer, parser and code generator. They operate purely on the String receiver,
// so they're extension functions on String (named with a `2` suffix to avoid
// colliding with any host builtin of the same bare name).

predicate String.startsWith2(prefix: String) {
    let pl = string_len(prefix)
    if string_len(this) < pl { return false }
    return string_slice(this, 0, pl) == prefix
}

predicate String.endsWith2(suffix: String) {
    let sl = string_len(suffix)
    let n = string_len(this)
    if n < sl { return false }
    return string_slice(this, n - sl, n) == suffix
}
