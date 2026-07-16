// xc parser — type-expression parsing -> ctype
// (part of the parser — spliced via the xc.xi manifest)

type TypeResult = { ctype: String, ps: PState }

mapper primKindToCtype(kind: Integer) -> String {
    match kind {
        260 -> "xc_number_t"
        261 -> "xc_integer_t"
        262 -> "xc_bool_t"
        263 -> "xc_string_t"
        264 -> "xc_char_t"
        265 -> "void"
        266 -> "xc_size_t"
        267 -> "const char*"
        268 -> "xc_bytes_t"
        269 -> "void*"
        _   -> ""
    }
}

mapper identToCtype(name: String) -> String => "xc_" + name + "_t"

mapper parseTypeExpr(ps: PState) -> TypeResult {
    let t = peek(ps)
    let base = ""
    let ps2 = ps

    // Primitive type keyword
    let pc = primKindToCtype(t.kind)
    if string_len(pc) > 0 {
        base = pc
        ps2 = advance(ps)
    } else {
        // &mut TypeExpr
        if t.kind == 124 {   // &mut
            ps2 = advance(ps)
            let inner = parseTypeExpr(ps2)
            return TypeResult { ctype: inner.ctype + "*", ps: inner.ps }
        }
        // & TypeExpr
        if t.kind == 123 {  // &
            ps2 = advance(ps)
            let inner = parseTypeExpr(ps2)
            return TypeResult { ctype: "const " + inner.ctype + "*", ps: inner.ps }
        }
        // own TypeExpr
        if t.kind == 232 {  // own
            ps2 = advance(ps)
            let inner = parseTypeExpr(ps2)
            return TypeResult { ctype: inner.ctype, ps: inner.ps }
        }
        // Function type  ( T1, T2 ) -> U  — a first-class closure value. Encoded
        // as Fn(<param ctypes>)(<ret ctype>); the C type is xc_fn_t (translated at
        // emission), the signature drives the call-site cast.
        if t.kind == 100 {  // (
            let pp = advance(ps)                  // past (
            let pcs = ""
            if peek(pp).kind != 101 {
                let pt0 = parseTypeExpr(pp)
                pcs = pt0.ctype
                pp = pt0.ps
                while peek(pp).kind == 106 {      // ,
                    pp = advance(pp)
                    let ptn = parseTypeExpr(pp)
                    pcs = pcs + "," + ptn.ctype
                    pp = ptn.ps
                }
            }
            if peek(pp).kind == 101 { pp = advance(pp) }   // )
            if peek(pp).kind == 109 { pp = advance(pp) }   // ->
            let rt = parseTypeExpr(pp)
            return TypeResult { ctype: "Fn(" + pcs + ")(" + rt.ctype + ")", ps: rt.ps }
        }
        // Compound type { field: type, ... }
        if t.kind == 102 {  // {
            // anonymous compound — skip for now, return void*
            ps2 = advance(ps)
            let depth = 1
            while depth > 0 {
                let ct = peek(ps2)
                if ct.kind == 102 { depth = depth + 1 }
                if ct.kind == 103 { depth = depth - 1 }
                ps2 = advance(ps2)
            }
            return TypeResult { ctype: "void*", ps: ps2 }
        }
        // Named type
        if t.kind == 1 {  // IDENT
            if t.text == "List" and peekAt(ps, 1).kind == 114 {  // List<T>
                let ep = advance(advance(ps))                    // past `List` and `<`
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_List_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Set" and peekAt(ps, 1).kind == 114 {   // Set<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Set_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Vec" and peekAt(ps, 1).kind == 114 {   // Vec<T> — alias of List<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_List_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Stack" and peekAt(ps, 1).kind == 114 {  // Stack<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Stack_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Queue" and peekAt(ps, 1).kind == 114 {  // Queue<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Queue_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "SortedQueue" and peekAt(ps, 1).kind == 114 {  // SortedQueue<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_SortedQueue_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Future" and peekAt(ps, 1).kind == 114 {  // Future<T>
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Future_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Query" and peekAt(ps, 1).kind == 114 {  // Query<T> — a reified query plan
                let ep = advance(advance(ps))
                let elem = parseTypeExpr(ep)
                ps2 = elem.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Query_" + ctypeSuffix(elem.ctype) + "_t"
            } else {
            if t.text == "Map" and peekAt(ps, 1).kind == 114 {   // Map<K, V>
                let kp = advance(advance(ps))                    // past `Map` and `<`
                let kt = parseTypeExpr(kp)
                let psA = kt.ps
                if peek(psA).kind == 106 { psA = advance(psA) }  // `,`
                let vt = parseTypeExpr(psA)
                ps2 = vt.ps
                if peek(ps2).kind == 115 { ps2 = advance(ps2) }  // `>`
                base = "xc_Map_" + ctypeSuffix(kt.ctype) + "_" + ctypeSuffix(vt.ctype) + "_t"
            } else {
                base = identToCtype(t.text)
                ps2 = advance(ps)
            } } } } } } } } }
        } else {
            return TypeResult { ctype: "void", ps: ps }
        }
    }

    // Postfix: ? or []
    let finalType = base
    let suf = ctypeSuffix(base)
    let ps3 = ps2
    let continuing = true
    while continuing {
        let pt = peek(ps3)
        if pt.kind == 127 {  // ?  optional
            ps3 = advance(ps3)
            finalType = "xc_opt_" + suf + "_t"
        } else {
            if pt.kind == 126 {  // !  Result-of-T (string error)
                ps3 = advance(ps3)
                finalType = "xc_res_" + suf + "_t"
            } else {
                if pt.kind == 104 and peekAt(ps3, 1).kind == 105 {  // []
                    ps3 = advance(advance(ps3))
                    finalType = "xc_arr_" + suf + "_t"
                } else {
                    continuing = false
                }
            }
        }
    }

    return TypeResult { ctype: finalType, ps: ps3 }
}

// Convert a base C type (e.g. "xc_string_t", "xc_Person_t") to the suffix
// used in xc_arr_<suffix>_t / xc_opt_<suffix>_t typedef names.
mapper ctypeSuffix(ctype: String) -> String {
    match ctype {
        "xc_number_t"    -> "number"
        "xc_integer_t"   -> "integer"
        "xc_bool_t"      -> "bool"
        "xc_string_t"    -> "string"
        "xc_char_t"      -> "char"
        "xc_size_t"      -> "size"
        "xc_timestamp_t" -> "timestamp"
        "void*"          -> "ptr"
        "const char*"    -> "cstring"
        _ -> {
            // otherwise strip leading "xc_" and trailing "_t"
            if string_len(ctype) > 5 { return string_slice(ctype, 3, string_len(ctype) - 2) }
            return ctype
        }
    }
}

// ── Collected declarations ────────────────────────────────────────

