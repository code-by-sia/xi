// xc codegen — xtype/ctype machinery.
//
// Single responsibility: the bidirectional mapping between X type names, their
// encoded xtype strings (Pair/Fn/List/Set/Stack/Queue/Map/Future), and C type
// spellings. Every helper is an operation on the type string (or token kind) it
// inspects, so they're extension functions on String / Integer / Token[].
// (Async wrappers + runWithDelay capture machinery moved to async_codegen.xi;
// GCtx param-seeding moved to gen_context.xi.)

mapper String.builtinForPath() -> String {
    match this {
        "system.stdout.writeln" -> "xc_stdout_writeln"
        "system.stdout.write"   -> "xc_stdout_write"
        "system.stderr.writeln" -> "xc_stderr_writeln"
        "system.stdin.readLine" -> "xc_stdin_readline"
        "system.process.exit"   -> "xc_process_exit"
        _ -> "0 /* unknown builtin */"
    }
}

// X type name -> C element type
mapper String.xnameToCtype() -> String {
    if this.isPairXType() { return "xc_pair_t" }
    if this.isFnXType() { return "xc_fn_t" }
    match this {
        "String"  -> "xc_string_t"
        "Number"  -> "xc_number_t"
        "Integer" -> "xc_integer_t"
        "Bool"    -> "xc_bool_t"
        "Char"    -> "xc_char_t"
        "Ptr"     -> "void*"
        "cstring" -> "const char*"
        _         -> "xc_" + this + "_t"
    }
}

// ── Pair<A,B> xtype encoding ──────────────────────────────────────────────────
// "Pair(" + aXtype + ")(" + bXtype + ")". Balanced parens let nested element
// types (e.g. Pair<List_integer, List_integer> from partition/unzip) parse
// unambiguously; the C representation is always the uniform xc_pair_t.
predicate String.isPairXType() { return this.startsWith2("Pair(") }
mapper String.pairXtype(b: String) -> String => "Pair(" + this + ")(" + b + ")"

// Closure type encoding: "Fn(" + csv-of-param-xtypes + ")(" + ret-xtype + ")".
// Balanced parens (group 0 = params, group 1 = return) reuse the Pair extractor,
// so nested function/Pair types parse unambiguously; the C type is always xc_fn_t.
predicate String.isFnXType() { return this.startsWith2("Fn(") }
mapper String.fnXtype(ret: String) -> String => "Fn(" + this + ")(" + ret + ")"
mapper String.fnParamsX() -> String => this.pairElem(0)
mapper String.fnRetX() -> String => this.pairElem(1)

// Content of the `which`-th (0|1) balanced-paren group in a Pair xtype.
mapper String.pairElem(which: Integer) -> String {
    let n = string_len(this)
    let i = 0
    let group = 0
    while i < n {
        if string_char_at(this, i) == 40 {          // '(' opens a group
            let depth = 1
            let start = i + 1
            let j = start
            while j < n and depth > 0 {
                let c = string_char_at(this, j)
                if c == 40 { depth = depth + 1 }
                if c == 41 { depth = depth - 1 }
                if depth > 0 { j = j + 1 }
            }
            if group == which { return string_slice(this, start, j) }
            group = group + 1
            i = j + 1
        } else {
            i = i + 1
        }
    }
    return ""
}

// X type name -> array typedef suffix
mapper String.arrSuffixOf() -> String {
    match this {
        "String"  -> "string"
        "Number"  -> "number"
        "Integer" -> "integer"
        "Bool"    -> "bool"
        "Char"    -> "char"
        _         -> this
    }
}

// array typedef suffix -> element X type name
mapper String.xnameFromArrSuffix() -> String {
    match this {
        "string"  -> "String"
        "number"  -> "Number"
        "integer" -> "Integer"
        "bool"    -> "Bool"
        "char"    -> "Char"
        _         -> this
    }
}

// ── List<T> element-type helpers (xtype "List_<suffix>") ──────────
predicate String.isListXType() { return this.startsWith2("List_") }
mapper String.listElemCtype() -> String {
    return string_slice(this, 5, string_len(this)).xnameFromArrSuffix().xnameToCtype()
}
mapper String.listElemXName() -> String {
    return string_slice(this, 5, string_len(this)).xnameFromArrSuffix()
}

// ── Set<T> element-type helpers (xtype "Set_<suffix>") ──────────
predicate String.isSetXType() { return this.startsWith2("Set_") }
mapper String.setElemCtype() -> String {
    return string_slice(this, 4, string_len(this)).xnameFromArrSuffix().xnameToCtype()
}
mapper String.setElemXName() -> String {
    return string_slice(this, 4, string_len(this)).xnameFromArrSuffix()
}
mapper String.setElemSuffix() -> String {
    return string_slice(this, 4, string_len(this))
}
// `1` if the element/key ctype is a String (hashed/compared by content), else `0`.
mapper String.strFlagFor() -> String {
    if this == "xc_string_t" { return "1" }
    return "0"
}

// ── Stack<T> / Queue<T> / SortedQueue<T> element helpers ──────────────────────
// xtypes "Stack_<suf>" (6), "Queue_<suf>" (6), "SortedQueue_<suf>" (12).
predicate String.isStackXType() { return this.startsWith2("Stack_") }
mapper String.stackElemSuffix() -> String { return string_slice(this, 6, string_len(this)) }
mapper String.stackElemCtype() -> String { return this.stackElemSuffix().xnameFromArrSuffix().xnameToCtype() }
mapper String.stackElemXName() -> String { return this.stackElemSuffix().xnameFromArrSuffix() }

predicate String.isQueueXType() { return this.startsWith2("Queue_") }
mapper String.queueElemSuffix() -> String { return string_slice(this, 6, string_len(this)) }
mapper String.queueElemCtype() -> String { return this.queueElemSuffix().xnameFromArrSuffix().xnameToCtype() }
mapper String.queueElemXName() -> String { return this.queueElemSuffix().xnameFromArrSuffix() }

predicate String.isSortedQueueXType() { return this.startsWith2("SortedQueue_") }
mapper String.sqElemSuffix() -> String { return string_slice(this, 12, string_len(this)) }
mapper String.sqElemCtype() -> String { return this.sqElemSuffix().xnameFromArrSuffix().xnameToCtype() }
mapper String.sqElemXName() -> String { return this.sqElemSuffix().xnameFromArrSuffix() }

// Min-heap comparison kind for SortedQueue from the element ctype:
// 1 = number (double), 2 = String (by content), 0 = integer/char/bool.
mapper String.pqCmpKind() -> String {
    if this == "xc_number_t" { return "1" }
    if this == "xc_string_t" { return "2" }
    return "0"
}

// ── Future<T> helpers (async / await) ────────────────────────────────────────
// xtype "Future_<suf>"; C type xc_Future_<suf>_t (== xc_Future_t).
predicate String.isFutureXType() { return this.startsWith2("Future_") }
mapper String.futureInnerSuffix() -> String { return string_slice(this, 7, string_len(this)) }
mapper String.futureInnerXName() -> String { return this.futureInnerSuffix().xnameFromArrSuffix() }
mapper String.futureInnerCtype() -> String { return this.futureInnerXName().xnameToCtype() }
// Is a C return type a Future (`xc_Future_<suf>_t`)?
predicate String.isFutureCtype() { return this.startsWith2("xc_Future_") }
// Inner C type of a Future C type: xc_Future_integer_t -> xc_integer_t.
mapper String.futureCtypeInner() -> String {
    let mid = string_slice(this, 10, string_len(this) - 2)   // strip "xc_Future_" .. "_t"
    return "xc_" + mid + "_t"
}
// Future xtype for an inner C type: xc_integer_t -> "Future_integer".
mapper String.futureXtypeFor() -> String { return "Future_" + ctypeSuffix(this) }

// ── Map<K,V> key/value helpers (xtype "Map_<ksuf>_<vsuf>") ──────────
// The key is always a primitive/String suffix, so its boundary is unambiguous.
predicate String.isMapXType() { return this.startsWith2("Map_") }
mapper String.mapKeySuffix() -> String {
    let rest = string_slice(this, 4, string_len(this))   // "<ksuf>_<vsuf>"
    if rest.startsWith2("integer_") { return "integer" }
    if rest.startsWith2("number_")  { return "number" }
    if rest.startsWith2("bool_")    { return "bool" }
    if rest.startsWith2("string_")  { return "string" }
    if rest.startsWith2("char_")    { return "char" }
    return ""
}
mapper String.mapValSuffix() -> String {
    let rest = string_slice(this, 4, string_len(this))
    let k = this.mapKeySuffix()
    return string_slice(rest, string_len(k) + 1, string_len(rest))
}
mapper String.mapKeyCtype() -> String { return this.mapKeySuffix().xnameFromArrSuffix().xnameToCtype() }
mapper String.mapValCtype() -> String { return this.mapValSuffix().xnameFromArrSuffix().xnameToCtype() }
mapper String.mapValXName() -> String { return this.mapValSuffix().xnameFromArrSuffix() }
mapper String.mapKeyXName() -> String { return this.mapKeySuffix().xnameFromArrSuffix() }

// Primitive token kind -> C type (for type annotations in let statements)
mapper Integer.primCtypeK() -> String {
    match this {
        260 -> "xc_number_t"
        261 -> "xc_integer_t"
        262 -> "xc_bool_t"
        263 -> "xc_string_t"
        264 -> "xc_char_t"
        265 -> "void"
        266 -> "xc_size_t"
        267 -> "const char*"
        269 -> "void*"
        _   -> ""
    }
}

// Read a type expression from a token stream and return its C type string.
mapper Token[].typeCtypeOf(start: Integer) -> String {
    let k = this.kindAt(start)
    let base = ""
    let p = start
    let pc = k.primCtypeK()
    if string_len(pc) > 0 {
        base = pc
        p = start + 1
    } else {
        if k == 1 {
            base = "xc_" + this.textAt(start) + "_t"
            p = start + 1
        } else {
            return "void*"
        }
    }
    let suf = ctypeSuffix(base)
    let result = base
    let cont = true
    while cont {
        let pk = this.kindAt(p)
        if pk == 127 {
            result = "xc_opt_" + suf + "_t"
            p = p + 1
        } else {
            if pk == 126 {
                result = "xc_res_" + suf + "_t"
                p = p + 1
            } else {
            if pk == 104 and this.kindAt(p + 1) == 105 {
                result = "xc_arr_" + suf + "_t"
                p = p + 2
            } else {
                cont = false
            }
            }
        }
    }
    return result
}

// Coerce a C expression to a string value for concatenation. (Written as a
// tabular `decision` — the compiler dogfooding its own decision-table feature:
// the `typ` column selects the wrapper, and the output expressions build on the
// `code` input.)
decision toStrC {
    in  code: String
    in  typ:  String
    out wrapped: String
    hit first
    | - | "String"  => code |
    | - | "Integer" => "xc_integer_to_string(" + code + ")" |
    | - | "Bool"    => "xc_bool_to_string(" + code + ")" |
    | - | "Number"  => "xc_number_to_string(" + code + ")" |
    | - | -         => "xc_number_to_string((xc_number_t)(" + code + "))" |
}
