// xc codegen — whole-program feature detection.
//
// Single responsibility: scan the program to decide which optional runtime
// facilities the generated C must pull in — threading, the std/web handler
// model, config-backed bindings, and JSON codecs. The token-stream probes are
// operations on a `Token[]` body; the program-level rollups are operations on
// `Program`.

// Does a token body reference threading (a `parallel` block or the `thread`
// facility)? Used to decide whether to derive codecs for channel payloads.
predicate Token[].usesThread() {
    let i = 0
    let n = tokenArrLen(this)
    while i < n {
        let t = tokenArrGet(this, i)
        if t.kind == 1 {
            if t.text == "parallel" { return true }
            if t.text == "thread" { return true }
        }
        i = i + 1
    }
    return false
}

// Does any body contain an identifier token `name`?
predicate Token[].hasIdent(name: String) {
    let i = 0
    let n = tokenArrLen(this)
    while i < n {
        let t = tokenArrGet(this, i)
        if t.kind == 1 and t.text == name { return true }
        i = i + 1
    }
    return false
}

// Does any body contain a token of kind `k`?
predicate Token[].hasKind(k: Integer) {
    let i = 0
    let n = tokenArrLen(this)
    while i < n { if tokenArrGet(this, i).kind == k { return true }  i = i + 1 }
    return false
}

predicate Program.usesThreads() {
    if this.entrySpec.bodyTokens.usesThread() { return true }
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n {
        if funcSpecGet(this.functions, i).bodyTokens.usesThread() { return true }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(this.classes)
    while ci < cn {
        let cs = classSpecGet(this.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            if methodSpecGet(cs.methList, mi).bodyTokens.usesThread() { return true }
            mi = mi + 1
        }
        ci = ci + 1
    }
    return false
}

// std/web's handler model is active when at least one class implements
// WebRequestHandler (controllers are auto-registered — no explicit bind needed).
predicate Program.webEnabled() {
    if not isInterface(this, "WebRequestHandler") { return false }
    return stringArrLen(implementorsOf(this, "WebRequestHandler")) > 0
}

// Any `bind I -> readConfig("...")` in the program?
predicate Program.usesConfig() {
    let i = 0
    let n = moduleSpecLen(this.modules)
    while i < n {
        let mod = moduleSpecGet(this.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            if string_len(bindSpecGet(mod.bindings, j).configPath) > 0 { return true }
            j = j + 1
        }
        i = i + 1
    }
    return false
}

// The config file path bound to interface `ifn`, or "" if it isn't config-backed.
mapper Program.configPathFor(ifn: String) -> String {
    let i = 0
    let n = moduleSpecLen(this.modules)
    let found = ""
    while i < n {
        let mod = moduleSpecGet(this.modules, i)
        let isTest = (mod.name == "Test")
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.ifaceName == ifn and string_len(b.configPath) > 0 {
                if isTest and this.inTestMode() { return b.configPath }   // Test config wins under XC_TEST
                if not isTest { found = b.configPath }
            }
            j = j + 1
        }
        i = i + 1
    }
    return found
}

// Does any function/entry/test/method body call `readConfig<T>(...)`?
predicate Program.progUsesReadConfig() {
    if this.entrySpec.bodyTokens.hasIdent("readConfig") { return true }
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n { if funcSpecGet(this.functions, i).bodyTokens.hasIdent("readConfig") { return true }  i = i + 1 }
    let ti = 0
    let tn = funcSpecLen(this.tests)
    while ti < tn { if funcSpecGet(this.tests, ti).bodyTokens.hasIdent("readConfig") { return true }  ti = ti + 1 }
    let ci = 0
    let cn = classSpecLen(this.classes)
    while ci < cn {
        let cs = classSpecGet(this.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn { if methodSpecGet(cs.methList, mi).bodyTokens.hasIdent("readConfig") { return true }  mi = mi + 1 }
        ci = ci + 1
    }
    return false
}

// Does any body use a `<json> as T` decode? (an `as` token, kind 209, inside an
// expression body — module `bind … as` is parsed separately, never in a body).
predicate Program.progUsesAsDecode() {
    if this.entrySpec.bodyTokens.hasKind(209) { return true }
    let i = 0
    let n = funcSpecLen(this.functions)
    while i < n { if funcSpecGet(this.functions, i).bodyTokens.hasKind(209) { return true }  i = i + 1 }
    let ti = 0
    let tn = funcSpecLen(this.tests)
    while ti < tn { if funcSpecGet(this.tests, ti).bodyTokens.hasKind(209) { return true }  ti = ti + 1 }
    let ci = 0
    let cn = classSpecLen(this.classes)
    while ci < cn {
        let cs = classSpecGet(this.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn { if methodSpecGet(cs.methList, mi).bodyTokens.hasKind(209) { return true }  mi = mi + 1 }
        ci = ci + 1
    }
    return false
}

predicate Program.codecsEnabled() {
    return this.webEnabled() or this.usesThreads() or this.usesConfig() or this.progUsesReadConfig() or this.progUsesAsDecode()
}

// A JSON codec (xc_tojson_/xc_fromjson_) is emitted for this X type: every event
// type, plus (when web or threading is in use, so channels can carry structured
// payloads) every compound type.
predicate Program.hasCodec(xn: String) {
    if this.isEventTypeC(xn) { return true }
    if this.isCompoundTypeC(xn) and this.codecsEnabled() { return true }
    return false
}
