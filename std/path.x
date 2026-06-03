// std/path — path string manipulation (pure X).  import "std/path.x"
namespace path

import "std/text.x"

// Last index of a single character code in s, or -1.
mapper lastIndexCode(s: String, code: Integer) -> Integer {
    let i = text.length(s) - 1
    while i >= 0 {
        if text.charAt(s, i) == code { return i }
        i = i - 1
    }
    return 0 - 1
}

// Join two path segments with a single separator.
mapper join(a: String, b: String) -> String {
    if text.length(a) == 0 { return b }
    if text.length(b) == 0 { return a }
    if text.endsWith(a, "/") { return a + b }
    return a + "/" + b
}

// Directory part of a path ("." if none).
mapper dirname(p: String) -> String {
    let i = lastIndexCode(p, 47)        // '/'
    if i < 0 { return "." }
    if i == 0 { return "/" }
    return text.substring(p, 0, i)
}

// Final path component.
mapper basename(p: String) -> String {
    let i = lastIndexCode(p, 47)        // '/'
    return text.substring(p, i + 1, text.length(p))
}

// Extension including the dot (e.g. ".x"), or "" if none.
mapper ext(p: String) -> String {
    let base = basename(p)
    let i = lastIndexCode(base, 46)     // '.'
    if i <= 0 { return "" }             // no dot, or a dotfile like ".bashrc"
    return text.substring(base, i, text.length(base))
}

// Path with its extension removed.
mapper stripExt(p: String) -> String {
    let e = ext(p)
    if text.length(e) == 0 { return p }
    return text.substring(p, 0, text.length(p) - text.length(e))
}
