// xc codegen — queries over the Program model.
//
// Single responsibility: answer "what does the program declare?" — name/kind
// predicates (is this a function / module / atom / machine / compound / extern?),
// refined-type resolution, and the X-type of a function/method/extern return or
// a compound field. All are read-only operations on `Program` (or on a C type/
// signature spelling), so they're extension functions on those receivers.

// Test build? `xi test` sets XC_TEST=1; in test mode the synthesized main runs
// the `test` cases and DI prefers `module Test` bindings over `module App`.
predicate Program.inTestMode() { return string_len(get_env("XC_TEST", "")) > 0 }

// Resolve a refined type name to its underlying primitive X-type name.
// e.g. NonEmpty -> String, Age -> Number. Compounds/interfaces pass through.
mapper Program.resolveX(xname: String) -> String {
    if xname == "String"  { return "String" }
    if xname == "Number"  { return "Number" }
    if xname == "Integer" { return "Integer" }
    if xname == "Bool"    { return "Bool" }
    if xname == "Char"    { return "Char" }
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == xname {
            if ts.isCompound {
                return xname
            }
            return ts.baseCtype.ctypeToXName()
        }
        i = i + 1
    }
    return xname
}

predicate Program.isModuleNameC(name: String) {
    let i = 0
    let n = moduleSpecLen(this.modules)
    while i < n {
        if moduleSpecGet(this.modules, i).name == name { return true }
        i = i + 1
    }
    return false
}

predicate Program.isFuncNameC(name: String) {
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        if funcSpecGet(this.functions, i).name == name { return true }
        i = i + 1
    }
    return false
}

predicate Program.isAtomNameC(name: String) {
    let i = 0
    let n = atomSpecLen(this.atoms)
    while i < n {
        if atomSpecGet(this.atoms, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper Program.atomStateTypeName(name: String) -> String {
    let i = 0
    let n = atomSpecLen(this.atoms)
    while i < n {
        let a = atomSpecGet(this.atoms, i)
        if a.name == name { return a.stateTypeName }
        i = i + 1
    }
    return ""
}

predicate Program.isMachineTypeC(name: String) {
    let i = 0
    let n = machineSpecLen(this.machines)
    while i < n {
        if machineSpecGet(this.machines, i).name == name { return true }
        i = i + 1
    }
    return false
}

// Is `name` (an X type name) a declared typed `event`?
predicate Program.isEventTypeC(name: String) {
    let i = 0
    let n = stringArrLen(this.eventTypes)
    while i < n {
        if stringArrGet(this.eventTypes, i) == name { return true }
        i = i + 1
    }
    return false
}

// Is `name` a declared compound (struct-like) type?
predicate Program.isCompoundTypeC(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == name and ts.isCompound { return true }
        i = i + 1
    }
    return false
}

mapper Program.funcRetXType(name: String) -> String {
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        let fs = funcSpecGet(this.functions, i)
        if fs.name == name {
            // `async` free function: callers receive a Future<T> over the inner T.
            // (A plain `-> Future<T>` already resolves to a Future xtype below.)
            if fs.isAsync {
                return fs.asyncInnerCtype().futureXtypeFor()
            }
            return this.resolveX(fs.retCtype.ctypeToXName())
        }
        i = i + 1
    }
    return ""
}

// Is `name` a method of class `cls`? Used to resolve unqualified (and recursive)
// calls inside a method body to a self-dispatched `xc_<cls>_<name>_impl` call.
predicate Program.isSelfMethodC(cls: String, name: String) {
    let i = 0
    let n = classSpecLen(this.classes)
    while i < n {
        let cs = classSpecGet(this.classes, i)
        if cs.name == cls {
            let mi = 0
            let mn = methodSpecLen(cs.methList)
            while mi < mn {
                if methodSpecGet(cs.methList, mi).name == name { return true }
                mi = mi + 1
            }
            return false
        }
        i = i + 1
    }
    return false
}

mapper Program.selfMethodRetXType(cls: String, name: String) -> String {
    let i = 0
    let n = classSpecLen(this.classes)
    while i < n {
        let cs = classSpecGet(this.classes, i)
        if cs.name == cls {
            let mi = 0
            let mn = methodSpecLen(cs.methList)
            while mi < mn {
                let ms = methodSpecGet(cs.methList, mi)
                if ms.name == name { return this.resolveX(ms.retCtype.ctypeToXName()) }
                mi = mi + 1
            }
        }
        i = i + 1
    }
    return ""
}

predicate Program.isExternNameC(name: String) {
    let i = 0
    let n = funcSpecLen(this.externs)
    while i < n {
        if funcSpecGet(this.externs, i).name == name { return true }
        i = i + 1
    }
    return false
}

mapper Program.externRetXType(name: String) -> String {
    let i = 0
    let n = funcSpecLen(this.externs)
    while i < n {
        let fs = funcSpecGet(this.externs, i)
        if fs.name == name { return this.resolveX(fs.retCtype.ctypeToXName()) }
        i = i + 1
    }
    return ""
}

predicate Program.isTypeNameC(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        if typeSpecGet(this.types, i).name == name { return true }
        i = i + 1
    }
    let j = 0
    let m = classSpecLen(this.classes)
    while j < m {
        if classSpecGet(this.classes, j).name == name { return true }
        j = j + 1
    }
    return false
}

// Is `name` a refined type carrying a `where` constraint?
predicate Program.isRefinedConstrained(name: String) {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == name {
            if not ts.isCompound {
                if ts.hasWhere { return true }
            }
        }
        i = i + 1
    }
    return false
}

// If compound `typeName`'s `field` has a constrained refined type, return the
// name of its check function (e.g. "xc_check_Age"); else "".
mapper Program.fieldCheckFn(typeName: String, field: String) -> String {
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == typeName {
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let fentry = stringArrGet(ts.fields, fi)
                let colon = findChar(fentry, 58)
                if string_slice(fentry, 0, colon) == field {
                    let fctype = string_slice(fentry, colon + 1, string_len(fentry))
                    let xname = fctype.ctypeToXName()
                    if this.isRefinedConstrained(xname) { return "xc_check_" + xname }
                    return ""
                }
                fi = fi + 1
            }
        }
        i = i + 1
    }
    return ""
}

mapper Program.fieldTypeNameC(typeName: String, field: String) -> String {
    // Result<T> fields: .ok is Bool, .err is String, .value is T.
    if field == "ok"  { return "Bool" }
    if field == "err" { return "String" }
    if typeName.startsWith2("res_") and field == "value" {
        let elem = string_slice(typeName, 4, string_len(typeName))
        return this.resolveX(elem.xnameFromArrSuffix())
    }
    let i = 0
    let n = typeSpecLen(this.types)
    while i < n {
        let ts = typeSpecGet(this.types, i)
        if ts.name == typeName {
            let fi = 0
            let fn2 = stringArrLen(ts.fields)
            while fi < fn2 {
                let fentry = stringArrGet(ts.fields, fi)
                let colon = findChar(fentry, 58)
                let fname = string_slice(fentry, 0, colon)
                if fname == field {
                    let fctype = string_slice(fentry, colon + 1, string_len(fentry))
                    return this.resolveX(fctype.ctypeToXName())
                }
                fi = fi + 1
            }
        }
        i = i + 1
    }
    return ""
}

// The X type of a class field accessed via `self.<field>` — a mutable state
// field or an injected dependency of class `cls` (or "" if neither).
mapper Program.classFieldXType(cls: String, field: String) -> String {
    let i = 0
    let n = classSpecLen(this.classes)
    while i < n {
        let cs = classSpecGet(this.classes, i)
        if cs.name == cls {
            let si = 0
            let sn = stringArrLen(cs.stateFields)
            while si < sn {
                let f = stringArrGet(cs.stateFields, si)
                let colon = findChar(f, 58)
                if string_slice(f, 0, colon) == field {
                    return this.resolveX(string_slice(f, colon + 1, string_len(f)).ctypeToXName())
                }
                si = si + 1
            }
            let di = 0
            let dn = depSpecLen(cs.depList)
            while di < dn {
                let dep = depSpecGet(cs.depList, di)
                if dep.name == field { return dep.ifaceName }
                di = di + 1
            }
        }
        i = i + 1
    }
    return ""
}

// The X type name of a listener method's first parameter (the event it handles),
// extracted from the C param string "xc_OrderPaid_t e[, ...]".
mapper String.firstParamXType() -> String {
    let n = string_len(this)
    let sp = 0
    while sp < n and string_char_at(this, sp) != 32 { sp = sp + 1 }
    if sp == 0 { return "" }
    return string_slice(this, 0, sp).ctypeToXName()
}
