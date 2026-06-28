// xc codegen — GCtx: the per-body code-generation context.
//
// Single responsibility: the immutable scope/symbol-table threaded through
// expression and statement codegen. It records local variables (name -> xtype),
// injected dependencies, the enclosing function's return ctype / mangled tag /
// class, and the params+deps capturable by `runWithDelay { }` blocks. Every
// mutator returns a fresh GCtx (value semantics), so codegen stays referentially
// transparent. The GCtx *shape* lives in core.xi; this file owns its behaviour.

// A program's fresh, empty codegen context.
mapper Program.newCtx() -> GCtx => GCtx { prog: this, symNames: [], symTypes: [], depNames: [], depTypes: [], retCtype: "", fnTag: "", selfClass: "", capNames: [], capTypes: [] }

mapper GCtx.withRet(ret: String) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: ret, fnTag: this.fnTag,
        selfClass: this.selfClass, capNames: this.capNames, capTypes: this.capTypes
    }
}

mapper GCtx.withTag(tag: String) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: this.retCtype, fnTag: tag,
        selfClass: this.selfClass, capNames: this.capNames, capTypes: this.capTypes
    }
}

// Mark the enclosing class so unqualified calls to sibling methods resolve to
// `xc_<Class>_<name>_impl(self, ...)`.
mapper GCtx.withSelfClass(cls: String) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: this.retCtype, fnTag: this.fnTag,
        selfClass: cls, capNames: this.capNames, capTypes: this.capTypes
    }
}

// Record the enclosing function's params+deps as the set capturable by a
// `runWithDelay { }` block (so its worker thread can see them by value).
mapper GCtx.withCaps(names: String[], types: String[]) -> GCtx {
    return GCtx {
        prog: this.prog, symNames: this.symNames, symTypes: this.symTypes,
        depNames: this.depNames, depTypes: this.depTypes, retCtype: this.retCtype, fnTag: this.fnTag,
        selfClass: this.selfClass, capNames: names, capTypes: types
    }
}

mapper GCtx.addSym(name: String, typ: String) -> GCtx {
    return GCtx {
        prog: this.prog,
        symNames: appendString(this.symNames, name),
        symTypes: appendString(this.symTypes, typ),
        depNames: this.depNames,
        depTypes: this.depTypes,
        retCtype: this.retCtype,
        fnTag: this.fnTag,
        selfClass: this.selfClass,
        capNames: this.capNames,
        capTypes: this.capTypes
    }
}

mapper GCtx.addDep(name: String, typ: String) -> GCtx {
    return GCtx {
        prog: this.prog,
        symNames: this.symNames,
        symTypes: this.symTypes,
        depNames: appendString(this.depNames, name),
        depTypes: appendString(this.depTypes, typ),
        retCtype: this.retCtype,
        fnTag: this.fnTag,
        selfClass: this.selfClass,
        capNames: this.capNames,
        capTypes: this.capTypes
    }
}

mapper GCtx.lookupVar(name: String) -> String {
    let i = 0
    let n = stringArrLen(this.symNames)
    while i < n {
        if stringArrGet(this.symNames, i) == name {
            return stringArrGet(this.symTypes, i)
        }
        i = i + 1
    }
    return ""
}

predicate GCtx.isDepNameC(name: String) {
    let i = 0
    let n = stringArrLen(this.depNames)
    while i < n {
        if stringArrGet(this.depNames, i) == name { return true }
        i = i + 1
    }
    return false
}

mapper GCtx.depTypeOf(name: String) -> String {
    let i = 0
    let n = stringArrLen(this.depNames)
    while i < n {
        if stringArrGet(this.depNames, i) == name {
            return stringArrGet(this.depTypes, i)
        }
        i = i + 1
    }
    return ""
}
