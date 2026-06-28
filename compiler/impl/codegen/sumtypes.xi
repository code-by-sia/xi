// xc codegen — sum / algebraic type helpers.
//
// Single responsibility: everything about declared sum types and their variants
// — locating the sum that owns a variant, testing whether a name is a variant,
// and lowering a variant's payload-field spec into a C struct body. Queries are
// operations on `Program`; the field-string lowering is an operation on the
// "f1:ct1,f2:ct2" String itself.

predicate Program.isSumTypeC(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == name and ts.isSum { return true }
        i = i + 1
    }
    return false
}

// The sum type that owns variant `vname` (or "" if none). Variant names must be
// globally unique across sum types.
mapper Program.sumOfVariant(vname: String) -> String {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.isSum {
            let vi = 0
            let vn = stringArrLen(ts.variants)
            while vi < vn {
                let v = stringArrGet(ts.variants, vi)
                let bar = findChar(v, 124)            // '|'
                if string_slice(v, 0, bar) == vname { return ts.name }
                vi = vi + 1
            }
        }
        i = i + 1
    }
    return ""
}

predicate Program.isVariantNameC(vname: String) => string_len(this.sumOfVariant(vname)) > 0

// The "f1:ct1,f2:ct2" field string for a variant ("" if it carries no payload).
mapper Program.variantFieldsC(sumName: String, vname: String) -> String {
    let ts = findTypeSpec(this, sumName)
    let vi = 0
    let vn = stringArrLen(ts.variants)
    while vi < vn {
        let v = stringArrGet(ts.variants, vi)
        let bar = findChar(v, 124)
        if string_slice(v, 0, bar) == vname { return string_slice(v, bar + 1, string_len(v)) }
        vi = vi + 1
    }
    return ""
}

// "f1:ct1,f2:ct2" -> "ct1 f1; ct2 f2; " for a C struct body.
mapper String.sumFieldsToC() -> String {
    let out = ""
    let n = string_len(this)
    if n == 0 { return out }
    let start = 0
    let i = 0
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(this, i) }
        if atEnd or c == 44 {                          // ','
            let seg = string_slice(this, start, i)
            let colon = findChar(seg, 58)              // ':'
            let fname = string_slice(seg, 0, colon)
            let fct = string_slice(seg, colon + 1, string_len(seg))
            out = out + fct + " " + fname + "; "
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return out
}
