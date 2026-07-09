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

// Does the name start with an ASCII uppercase letter? Type / event / variant
// names are Capitalized by convention, so this gates type-shaped diagnostics.
predicate String.startsUpper() {
    if string_len(this) == 0 { return false }
    let c = string_char_at(this, 0)
    return c >= 65 and c <= 90
}

// Membership test over a String[] — `names.includes(x)`. Lets a long run of
// `if x == "a" { return true } ...` collapse to a single set-style query.
predicate String[].includes(s: String) {
    let i = 0
    while i < this.len {
        if this.data[i] == s { return true }
        i = i + 1
    }
    return false
}
