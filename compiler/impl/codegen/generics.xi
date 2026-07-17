// xc codegen — generic interface monomorphization. (spliced via xc.xi)

// Rebuild a Program swapping only its interface + class lists (the monomorphized
// sets); every other field is carried through unchanged.
mapper Program.withMono(ifaces: IfaceSpec[], classes: ClassSpec[]) -> Program {
    return Program {
        types: this.types, ifaces: ifaces, classes: classes,
        modules: this.modules, functions: this.functions, externs: this.externs,
        entrySpec: this.entrySpec, interrupts: this.interrupts, atoms: this.atoms,
        machines: this.machines, eventTypes: this.eventTypes, tables: this.tables,
        tests: this.tests, scheduled: this.scheduled, libraries: this.libraries,
        infixFns: this.infixFns, cIncludes: this.cIncludes, cFlags: this.cFlags
    }
}

//
// A generic interface (typeParams non-empty) is a template. For each class that
// implements a concrete instantiation `Base<A1, A2>`, we synthesize a concrete
// non-generic interface with the type parameters textually substituted, so all
// the existing vtable / caster / default-method codegen works unchanged. The
// class's `implements` entry is rewritten to the mangled concrete name, and any
// interfaces the template `extends` are flattened in (their substituted methods
// copied down) and added to the class so casts to a base interface also work.
//
// This runs once, right after parsing, producing a Program with the generic
// templates removed and the concrete instantiations added.

// "Integer,User" -> ["Integer","User"]  ("" -> [])
mapper splitCsv(s: String) -> String[] {
    let out: String[] = []
    if string_len(s) == 0 { return out }
    let start = 0
    let i = 0
    let n = string_len(s)
    while i <= n {
        let atSep = i == n
        if not atSep { if string_char_at(s, i) == 44 { atSep = true } }   // ','
        if atSep {
            out = appendString(out, string_slice(s, start, i))
            start = i + 1
        }
        i = i + 1
    }
    return out
}

// mangled concrete interface name:  Base<Integer,User>  ->  Base_Integer_User
mapper monoName(base: String, argsCsv: String) -> String {
    return base + "_" + argsCsv.replaceAll(",", "_")
}

// The ctype-suffix form of an Xi type name (Integer -> integer, User -> User),
// so substitution into a ctype string produces the right primitive casing.
mapper ctypeSuffixOf(xname: String) -> String {
    let ct = xname.xnameToCtype()
    if ct.startsWith2("xc_") and ct.endsWith2("_t") { return string_slice(ct, 3, string_len(ct) - 2) }
    return xname
}

// substitute each type param -> its arg inside a ctype / params string. Type
// vars in a ctype are always underscore-bounded (`xc_T_t`, `xc_opt_T_t`,
// `xc_arr_T_t`), so match `_<param>_` to avoid clobbering an unrelated name that
// merely contains the param as a substring (e.g. T inside Timestamp). The arg is
// substituted in its ctype-suffix form (Integer -> integer).
mapper substStr(s: String, params: String[], args: String[]) -> String {
    let out = s
    let i = 0
    while i < stringArrLen(params) {
        if i < stringArrLen(args) {
            out = out.replaceAll("_" + stringArrGet(params, i) + "_", "_" + ctypeSuffixOf(stringArrGet(args, i)) + "_")
        }
        i = i + 1
    }
    return out
}

// substitute type params in a method's default-body tokens (identifier text)
mapper substTokens(toks: Token[], params: String[], args: String[]) -> Token[] {
    let out: Token[] = []
    let i = 0
    let n = tokenArrLen(toks)
    while i < n {
        let t = tokenArrGet(toks, i)
        let txt = t.text
        if t.kind == 1 {
            let p = 0
            while p < stringArrLen(params) {
                if txt == stringArrGet(params, p) and p < stringArrLen(args) { txt = stringArrGet(args, p) }
                p = p + 1
            }
        }
        out = appendToken(out, Token { kind: t.kind, text: txt, line: t.line, file: t.file })
        i = i + 1
    }
    return out
}

mapper substMethod(ms: MethodSpec, params: String[], args: String[]) -> MethodSpec {
    return MethodSpec {
        isAsync: ms.isAsync, kind: ms.kind, name: ms.name,
        params: substStr(ms.params, params, args),
        retCtype: substStr(ms.retCtype, params, args),
        bodyTokens: substTokens(ms.bodyTokens, params, args),
        topic: ms.topic, hasWhere: ms.hasWhere,
        whereTokens: substTokens(ms.whereTokens, params, args),
        fnDeps: ms.fnDeps
    }
}

// Substitute type params in an args list "TKey,TEntity" -> "Integer,User" — a
// name-level (not ctype) substitution, used for an extended interface's args
// which feed the mangled name.
mapper substArgs(argsCsv: String, params: String[], args: String[]) -> String {
    let parts = splitCsv(argsCsv)
    let out = ""
    let i = 0
    while i < stringArrLen(parts) {
        let repl = stringArrGet(parts, i)
        let j = 0
        while j < stringArrLen(params) {
            if repl == stringArrGet(params, j) and j < stringArrLen(args) { repl = stringArrGet(args, j) }
            j = j + 1
        }
        if string_len(out) > 0 { out = out + "," }
        out = out + repl
        i = i + 1
    }
    return out
}

mapper findGenericIface(prog: Program, name: String) -> IfaceSpec {
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        if is2.name == name { return is2 }
        i = i + 1
    }
    return IfaceSpec { name: "", extendsNames: [], methList: [], typeParams: [], extendsArgs: [] }
}

predicate ifaceAccHas(acc: IfaceSpec[], name: String) {
    let d = 0
    while d < ifaceSpecLen(acc) { if ifaceSpecGet(acc, d).name == name { return true }  d = d + 1 }
    return false
}

// Synthesize the concrete interface for Base<argsCsv> plus every generic
// interface it (transitively) extends, appending them to `acc` (deduped). The
// concrete methList flattens in the substituted methods of extended interfaces.
mapper synthIface(prog: Program, base: String, argsCsv: String, acc: IfaceSpec[]) -> IfaceSpec[] {
    let mangled = monoName(base, argsCsv)
    if ifaceAccHas(acc, mangled) { return acc }

    let tmpl = findGenericIface(prog, base)
    let params = tmpl.typeParams
    let args = splitCsv(argsCsv)

    // this interface's own (substituted) methods
    let methList: MethodSpec[] = []
    let mi = 0
    while mi < methodSpecLen(tmpl.methList) {
        methList = appendMethodSpec(methList, substMethod(methodSpecGet(tmpl.methList, mi), params, args))
        mi = mi + 1
    }
    // flatten extended interfaces: substitute their args, synth them, copy methods down
    let exNames: String[] = []
    let ei = 0
    while ei < stringArrLen(tmpl.extendsNames) {
        let bn = stringArrGet(tmpl.extendsNames, ei)
        let ba = ""
        if ei < stringArrLen(tmpl.extendsArgs) { ba = substArgs(stringArrGet(tmpl.extendsArgs, ei), params, args) }
        if string_len(ba) > 0 {
            let baseM = monoName(bn, ba)
            exNames = appendString(exNames, baseM)
            acc = synthIface(prog, bn, ba, acc)
            // copy the base's (already substituted) methods into this vtable
            let bi = 0
            while bi < ifaceSpecLen(acc) {
                let cand = ifaceSpecGet(acc, bi)
                if cand.name == baseM {
                    let cm = 0
                    while cm < methodSpecLen(cand.methList) {
                        methList = appendMethodSpec(methList, methodSpecGet(cand.methList, cm))
                        cm = cm + 1
                    }
                }
                bi = bi + 1
            }
        } else {
            exNames = appendString(exNames, bn)
        }
        ei = ei + 1
    }
    let concrete = IfaceSpec { name: mangled, extendsNames: exNames, methList: methList,
                              typeParams: [], extendsArgs: [] }
    return appendIfaceSpec(acc, concrete)
}

// All concrete interface names (self + transitive generic bases) for Base<args>.
mapper monoChain(prog: Program, base: String, argsCsv: String, out: String[]) -> String[] {
    let mangled = monoName(base, argsCsv)
    if strArrContains(out, mangled) { return out }
    out = appendString(out, mangled)
    let tmpl = findGenericIface(prog, base)
    let ei = 0
    while ei < stringArrLen(tmpl.extendsNames) {
        let ba = ""
        if ei < stringArrLen(tmpl.extendsArgs) {
            ba = substArgs(stringArrGet(tmpl.extendsArgs, ei), tmpl.typeParams, splitCsv(argsCsv))
        }
        if string_len(ba) > 0 { out = monoChain(prog, stringArrGet(tmpl.extendsNames, ei), ba, out) }
        ei = ei + 1
    }
    return out
}

predicate Program.isGenericIfaceName(name: String) {
    let i = 0
    let n = ifaceSpecLen(this.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(this.ifaces, i)
        if is2.name == name and stringArrLen(is2.typeParams) > 0 { return true }
        i = i + 1
    }
    return false
}

predicate matHasMethod(ms: MethodSpec[], name: String) {
    let i = 0
    while i < methodSpecLen(ms) { if methodSpecGet(ms, i).name == name { return true }  i = i + 1 }
    return false
}

mapper ifaceByName(acc: IfaceSpec[], name: String) -> IfaceSpec {
    let i = 0
    while i < ifaceSpecLen(acc) {
        if ifaceSpecGet(acc, i).name == name { return ifaceSpecGet(acc, i) }
        i = i + 1
    }
    return IfaceSpec { name: "", extendsNames: [], methList: [], typeParams: [], extendsArgs: [] }
}

// A concrete interface method stripped of its default body — so the class that
// implements it supplies the code (materialized, see below) and no shared
// `_default_impl` is emitted for a body that may reach into `this`.
mapper stripBody(ms: MethodSpec) -> MethodSpec {
    return MethodSpec {
        isAsync: ms.isAsync, kind: ms.kind, name: ms.name, params: ms.params,
        retCtype: ms.retCtype, bodyTokens: [], topic: ms.topic,
        hasWhere: ms.hasWhere, whereTokens: [], fnDeps: ms.fnDeps
    }
}

// The whole pass: rewrite classes' generic implements to concrete names and
// return a Program whose ifaces = (non-generic originals) + (synthesized).
//
// Generic interface defaults are **materialized** into each implementing class:
// an un-overridden default method is copied (already type-substituted) into the
// class's own methList, so its body dispatches to sibling methods on `this`
// (getProvider / source / findAll ...) through normal class-method codegen. The
// synthesized interface then carries the method as abstract.
mapper monomorphize(prog: Program) -> Program {
    let synth: IfaceSpec[] = []
    let newClasses: ClassSpec[] = []

    let ci = 0
    while ci < classSpecLen(prog.classes) {
        let cs = classSpecGet(prog.classes, ci)
        let newImpl: String[] = []
        let matMeths: MethodSpec[] = []     // default methods materialized into this class
        let ii = 0
        while ii < stringArrLen(cs.implNames) {
            let ifn = stringArrGet(cs.implNames, ii)
            let arg = ""
            if ii < stringArrLen(cs.implArgs) { arg = stringArrGet(cs.implArgs, ii) }
            if string_len(arg) > 0 and prog.isGenericIfaceName(ifn) {
                // this + every generic base become concrete implemented interfaces
                let chain = monoChain(prog, ifn, arg, emptyStrings())
                let k = 0
                while k < stringArrLen(chain) {
                    if not strArrContains(newImpl, stringArrGet(chain, k)) {
                        newImpl = appendString(newImpl, stringArrGet(chain, k))
                    }
                    k = k + 1
                }
                synth = synthIface(prog, ifn, arg, synth)
                // materialize un-overridden defaults from the top concrete interface
                // (its methList already flattens every extended interface's methods)
                let top = ifaceByName(synth, monoName(ifn, arg))
                let tm = 0
                while tm < methodSpecLen(top.methList) {
                    let m = methodSpecGet(top.methList, tm)
                    if tokenArrLen(m.bodyTokens) > 0 and countMethodName(cs, m.name) == 0
                       and not matHasMethod(matMeths, m.name) {
                        matMeths = appendMethodSpec(matMeths, m)
                    }
                    tm = tm + 1
                }
            } else {
                newImpl = appendString(newImpl, ifn)
            }
            ii = ii + 1
        }
        let finalMeths = cs.methList
        let mm = 0
        while mm < methodSpecLen(matMeths) {
            finalMeths = appendMethodSpec(finalMeths, methodSpecGet(matMeths, mm))
            mm = mm + 1
        }
        newClasses = appendClassSpec(newClasses, ClassSpec {
            name: cs.name, implNames: newImpl, depList: cs.depList, methList: finalMeths,
            stateFields: cs.stateFields, stateInit: cs.stateInit, implArgs: cs.implArgs
        })
        ci = ci + 1
    }

    // final ifaces: keep non-generic originals, drop templates, add synthesized.
    // Synthesized interface methods are stripped to abstract — every implementing
    // class carries the body (its own override or a materialized default).
    let newIfaces: IfaceSpec[] = []
    let fi = 0
    while fi < ifaceSpecLen(prog.ifaces) {
        let is2 = ifaceSpecGet(prog.ifaces, fi)
        if stringArrLen(is2.typeParams) == 0 { newIfaces = appendIfaceSpec(newIfaces, is2) }
        fi = fi + 1
    }
    let si = 0
    while si < ifaceSpecLen(synth) {
        let sIf = ifaceSpecGet(synth, si)
        let absMeths: MethodSpec[] = []
        let am = 0
        while am < methodSpecLen(sIf.methList) {
            absMeths = appendMethodSpec(absMeths, stripBody(methodSpecGet(sIf.methList, am)))
            am = am + 1
        }
        newIfaces = appendIfaceSpec(newIfaces, IfaceSpec {
            name: sIf.name, extendsNames: sIf.extendsNames, methList: absMeths,
            typeParams: [], extendsArgs: []
        })
        si = si + 1
    }

    return prog.withMono(newIfaces, newClasses)
}
