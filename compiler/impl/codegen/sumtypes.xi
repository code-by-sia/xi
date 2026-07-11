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

// The X type of one payload field of `sumName`.`vname` ("" if no such field).
// Used by member access on a match binding (xtype "vpay:<Sum>:<Variant>") so a
// payload field of container type (List<T>, T[], Map<...>) keeps its element
// typing — e.g. `for a in c.args` iterates a List payload correctly.
mapper Program.variantFieldXType(sumName: String, vname: String, field: String) -> String {
    let fstr = this.variantFieldsC(sumName, vname)
    let n = string_len(fstr)
    if n == 0 { return "" }
    let start = 0
    let i = 0
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(fstr, i) }
        if atEnd or c == 44 {                          // ','
            let seg = string_slice(fstr, start, i)
            let colon = findChar(seg, 58)              // ':'
            if string_slice(seg, 0, colon) == field {
                let fct = string_slice(seg, colon + 1, string_len(seg))
                return this.resolveX(fct.ctypeToXName())
            }
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return ""
}

// Does variant `vname` of `sumName` declare a field literally named `field`?
predicate Program.variantHasFieldC(sumName: String, vname: String, field: String) {
    let fstr = this.variantFieldsC(sumName, vname)
    let n = string_len(fstr)
    if n == 0 { return false }
    let start = 0
    let i = 0
    let cont = true
    while cont {
        let atEnd = i == n
        let c = 0
        if not atEnd { c = string_char_at(fstr, i) }
        if atEnd or c == 44 {
            let seg = string_slice(fstr, start, i)
            let colon = findChar(seg, 58)
            if string_slice(seg, 0, colon) == field { return true }
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return false
}

// "f1:ct1,f2:ct2" -> "ct1 f1; ct2 f2; " for a C struct body. A field whose type
// is the enclosing sum type itself (direct recursion, e.g. Bin { left: Expr })
// is auto-boxed: emitted as a pointer, so the tree can nest to any depth.
// Construction boxes (xc_box_<Sum>) and field access derefs — invisible in Xi.
mapper String.sumFieldsToCFor(sumName: String) -> String {
    let selfCt = "xc_" + sumName + "_t"
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
            if fct == selfCt {
                out = out + "struct xc_" + sumName + "_s* " + fname + "; "
            } else {
                out = out + fct + " " + fname + "; "
            }
            start = i + 1
        }
        if atEnd { cont = false }
        i = i + 1
    }
    return out
}

// Does the sum type have any directly self-referential (boxed) payload field?
predicate Program.sumHasBoxedFields(sumName: String) {
    let ts = findTypeSpec(this, sumName)
    let vi = 0
    let vn = stringArrLen(ts.variants)
    while vi < vn {
        let v = stringArrGet(ts.variants, vi)
        if containsSub(v + ",", ":xc_" + sumName + "_t,") { return true }
        vi = vi + 1
    }
    return false
}

// Is `field` of `sumName`.`vname` a boxed (self-referential) payload field?
predicate Program.variantFieldBoxed(sumName: String, vname: String, field: String) {
    let fstr = this.variantFieldsC(sumName, vname)
    return containsSub("," + fstr + ",", "," + field + ":xc_" + sumName + "_t,")
}
