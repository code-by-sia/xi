// xc code generator — Program -> C99 (foundation)
//
// This file holds only the shared vocabulary of the code generator: the result
// types threaded through expression/statement codegen, the Token[] accessors,
// and the lowest-level C-emission / ctype-bridge helpers everything else builds
// on. Behaviour with a single, narrower responsibility lives in sibling files:
//   gen_context.xi   — the GCtx scope/symbol-table context
//   program_query.xi — name/type/return/field queries over the Program model
//   sumtypes.xi      — sum/algebraic type helpers
//   machines.xi      — state-machine codegen helpers
//   feature_detect.xi— whole-program feature/codec detection

// `owned` = the expression yields a freshly-owned heap value (rc 1) the
// consumer must release, vs a borrowed/aliased value (variable, field,
// literal) it must not. Drives ARC retain/release insertion (Phase 3).
type ExprRes = { code: String, pos: Integer, xtyp: String, owned: Bool }
type GArgs   = { code: String, pos: Integer, firstRaw: String }

type GCtx = {
    prog:     Program,
    symNames: String[],
    symTypes: String[],
    depNames: String[],
    depTypes: String[],
    retCtype: String,
    fnTag:    String,       // mangled name of the enclosing fn (for catch helpers)
    selfClass: String,      // enclosing class name in a method body ("" otherwise)
    capNames: String[],     // params+deps capturable by `runWithDelay { }` blocks
    capTypes: String[]      // their C types (index-matched with capNames)
}

type StmtRes = { code: String, ctx: GCtx, pos: Integer }

// ── token access helpers ─────────────────────────────────────────
mapper Token[].kindAt(i: Integer) -> Integer => tokenArrGet(this, i).kind
mapper Token[].textAt(i: Integer) -> String => tokenArrGet(this, i).text

// index of the } matching the { at openIdx
mapper Token[].matchBrace(openIdx: Integer) -> Integer {
    let depth = 0
    let p = openIdx
    let n = tokenArrLen(this)
    let result = openIdx
    let cont = true
    while cont and p < n {
        let k = this.kindAt(p)
        if k == 102 {
            depth = depth + 1
        } else {
            if k == 103 {
                depth = depth - 1
                if depth == 0 {
                    result = p
                    cont = false
                }
            }
        }
        p = p + 1
    }
    return result
}

// Escape a string for embedding in a C string literal (backslash and quote).
mapper String.cEscape() -> String {
    let n = string_len(this)
    let out = ""
    let runStart = 0
    let i = 0
    while i < n {
        let c = string_char_at(this, i)
        if c == 34 or c == 92 {     // " or backslash
            out = out + string_slice(this, runStart, i) + "\\" + string_slice(this, i, i + 1)
            runStart = i + 1
        }
        i = i + 1
    }
    return out + string_slice(this, runStart, n)
}

// Map a C type spelling to its X-type name (the inverse of type lowering). The
// ctype↔xtype bridge used throughout codegen, hence its place in the foundation.
mapper String.ctypeToXName() -> String {
    if this.isFnXType() { return this }    // Fn(...)/Pair(...) carry their own
    if this.isPairXType() { return this }  // signature; they're already xtypes
    match this {
        "xc_string_t"  -> "String"
        "xc_number_t"  -> "Number"
        "xc_integer_t" -> "Integer"
        "xc_bool_t"    -> "Bool"
        "xc_char_t"    -> "Char"
        "xc_size_t"    -> "Size"
        "void*"        -> "Ptr"
        "const char*"  -> "cstring"
        _ -> {
            // strip leading "xc_" and trailing "_t"
            if string_len(this) > 5 { return string_slice(this, 3, string_len(this) - 2) }
            return ""
        }
    }
}
