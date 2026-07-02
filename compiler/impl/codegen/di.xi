// xc codegen — dependency injection: ctors, resolvers, factories, singletons, config
// (part of the generator — spliced via the xc.xi manifest)

// Emit C statements that wire one dependency into `target` (e.g. "o->logger").
mapper wireDep(prog: Program, dep: DepSpec, target: String) -> String {
    let j = dep.ifaceName
    let form = dep.form

    if form == "list" {
        let impls = implementorsOf(prog, j)
        let nimp = stringArrLen(impls)
        let out = "    { xc_arr_" + j + "_t _a; _a.len = " + int_to_string(nimp) + "; _a.cap = " + int_to_string(nimp) + ";\n"
        if nimp == 0 {
            out = out + "      _a.data = (xc_" + j + "_t*)0;\n"
        } else {
            out = out + "      _a.data = (xc_" + j + "_t*)malloc(" + int_to_string(nimp) + " * sizeof(xc_" + j + "_t));\n"
            let k = 0
            while k < nimp {
                let impl = stringArrGet(impls, k)
                out = out + "      _a.data[" + int_to_string(k) + "] = xc_" + impl + "_as_" + j + "(xc_new_" + impl + "());\n"
                k = k + 1
            }
        }
        return out + "      " + target + " = _a; }\n"
    }

    if form == "where" {
        let impls = implementorsOf(prog, j)
        let nimp = stringArrLen(impls)
        let gctx = (prog.newCtx()).addSym(dep.name, j)
        let cond = genExpr(dep.whereTokens, 0, gctx)
        let out = "    { bool _ok = false;\n"
        let k = 0
        while k < nimp {
            let impl = stringArrGet(impls, k)
            out = out + "      if (!_ok) { xc_" + j + "_t " + dep.name + " = xc_" + impl + "_as_" + j + "(xc_new_" + impl + "());\n"
            out = out + "        if (" + cond.code + ") { " + target + " = " + dep.name + "; _ok = true; } }\n"
            k = k + 1
        }
        if nimp > 0 {
            let first = stringArrGet(impls, 0)
            out = out + "      if (!_ok) { " + target + " = xc_" + first + "_as_" + j + "(xc_new_" + first + "()); }\n"
        }
        return out + "    }\n"
    }

    if form == "or" {
        let chosen = orChoose(prog, j, dep.orAlt)
        if string_len(chosen) == 0 { return "    /* dep " + dep.name + ": unresolved */\n" }
        return "    " + target + " = xc_" + chosen + "_as_" + j + "(xc_new_" + chosen + "());\n"
    }

    if form == "opt" {
        if isResolvable(prog, j) {
            return "    " + target + ".has_value = true; " + target + ".value = xc_resolve_" + j + "();\n"
        }
        return "    /* optional dep " + dep.name + ": none */\n"
    }

    // single
    if isInterface(prog, j) {
        if isResolvable(prog, j) {
            return "    " + target + " = xc_resolve_" + j + "();\n"
        }
        return "    /* dep " + dep.name + ": no implementor of " + j + " */\n"
    }
    return "    /* dep " + dep.name + ": non-interface */\n"
}

// Forward declarations so constructors/resolvers can mutually recurse.
// Refined-type constraint checkers: xc_check_<T>(value) aborts on violation.
mapper genCheckFns(prog: Program) -> String {
    let out = "/* === Refined-type constraint checks === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not ts.isCompound {
            if ts.hasWhere {
                let base = ts.baseCtype
                let ctx = (prog.newCtx()).addSym("value", base.ctypeToXName())
                let cond = genExpr(ts.whereTokens, 0, ctx)
                out = out + "static " + base + " xc_check_" + ts.name + "(" + base + " value) {\n"
                out = out + "    XC_CONSTRAINT_CHECK(" + cond.code + ", \"" + ts.name + "\");\n"
                out = out + "    return value;\n}\n"
            }
        }
        i = i + 1
    }
    return out + "\n"
}

mapper genCtorResolverFwd(prog: Program) -> String {
    let out = "/* === DI forward declarations === */\n"
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        out = out + "static xc_" + cs.name + "_t* xc_new_" + cs.name + "(void);\n"
        i = i + 1
    }
    let j = 0
    let m = ifaceSpecLen(prog.ifaces)
    while j < m {
        let is2 = ifaceSpecGet(prog.ifaces, j)
        out = out + "static xc_" + is2.name + "_t xc_resolve_" + is2.name + "(void);\n"
        j = j + 1
    }
    return out + "\n"
}

// Module-scoped `const NAME: T = expr` -> a getter `xc_<Module>_<NAME>()`.
// Referenced anywhere as `Module.NAME`. Forward-declared first so consts may
// reference earlier consts (and each other across modules).
mapper genModuleConsts(prog: Program) -> String {
    let fwd = ""
    let defs = ""
    let mi = 0
    let mn = moduleSpecLen(prog.modules)
    while mi < mn {
        let mod = moduleSpecGet(prog.modules, mi)
        let ci = 0
        let cn = stringArrLen(mod.constNames)
        while ci < cn {
            let f = stringArrGet(mod.constNames, ci)
            let colon = findChar(f, 58)
            let nm = string_slice(f, 0, colon)
            let ct = string_slice(f, colon + 1, string_len(f))
            fwd = fwd + "static " + ct + " xc_" + mod.name + "_" + nm + "(void);\n"
            ci = ci + 1
        }
        let cinit = mod.constInit
        let cp = 0
        let ictx = prog.newCtx()
        while cinit.kindAt(cp) != 0 {
            let nm = cinit.textAt(cp)
            cp = cp + 1
            if cinit.kindAt(cp) == 111 { cp = cp + 1 }   // =
            let e = genExpr(cinit, cp, ictx)
            cp = e.pos
            defs = defs + "static " + mod.constCtype(nm) + " xc_" + mod.name + "_" + nm + "(void) { return " + e.code + "; }\n"
        }
        mi = mi + 1
    }
    if string_len(fwd) == 0 { return "" }
    return "/* === Module consts === */\n" + fwd + defs + "\n"
}

// Per-class heap constructor that auto-wires its dependencies.
mapper genConstructors(prog: Program) -> String {
    let out = "/* === DI constructors === */\n"
    let i = 0
    let n = classSpecLen(prog.classes)
    while i < n {
        let cs = classSpecGet(prog.classes, i)
        let cn = cs.name
        out = out + $"""
            static xc_${cn}_t* xc_new_${cn}(void) {
                xc_${cn}_t* o = (xc_${cn}_t*)xc_obj_alloc(sizeof(xc_${cn}_t));
                if (!o) abort();
                memset(o, 0, sizeof(xc_${cn}_t));
            """
        let di = 0
        let dn = depSpecLen(cs.depList)
        while di < dn {
            let dep = depSpecGet(cs.depList, di)
            out = out + wireDep(prog, dep, "o->" + dep.name)
            di = di + 1
        }
        // mutable state fields: run each `name = expr` initializer into o->name
        let sinit = cs.stateInit
        let sp = 0
        let ictx = prog.newCtx()
        while sinit.kindAt(sp) != 0 {
            let fname = sinit.textAt(sp)
            sp = sp + 1
            if sinit.kindAt(sp) == 111 { sp = sp + 1 }   // =
            let e = genExpr(sinit, sp, ictx)
            sp = e.pos
            out = out + "    o->" + fname + " = " + e.code + ";\n"
            if sinit.kindAt(sp) == 106 { sp = sp + 1 }   // ,
        }
        out = out + "    return o;\n}\n\n"
        i = i + 1
    }
    return out + "\n"
}

// Per-interface resolver: bind override or sole implementor; singleton or fresh.
// Config-backed implementors: a vtable whose methods read the parsed config tree
// by method name and decode into each method's return type.
mapper genConfigImpls(prog: Program) -> String {
    if not prog.usesConfig() { return "" }
    let out = """
        /* === Config-backed interface implementors === */
        extern xc_string_t file_read_all(xc_string_t);
        extern xc_Json_t xstd_json_parse(xc_string_t);
        extern xc_Json_t xstd_yaml_parse(xc_string_t);
        extern xc_Json_t xstd_json_get(xc_Json_t, xc_string_t);
        extern xc_string_t xstd_json_as_string(xc_Json_t);
        extern xc_number_t xstd_json_as_number(xc_Json_t);
        extern xc_bool_t xstd_json_as_bool(xc_Json_t);
        """
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        let ifn = is2.name
        if string_len(prog.configPathFor(ifn)) > 0 {
            let mn = methodSpecLen(is2.methList)
            let mi = 0
            while mi < mn {
                let ms = methodSpecGet(is2.methList, mi)
                let dec = jsonDecodeExpr(prog, ms.retCtype, "xstd_json_get(_t, xc_string_from_cstr(\"" + ms.name + "\"))")
                out = out + "static " + ms.retCtype + " xc_" + ifn + "__" + ms.name + "_cfg(void* self) {\n"
                out = out + "    xc_Json_t _t = (xc_Json_t)self; (void)_t;\n"
                if string_len(dec) > 0 {
                    out = out + "    return " + dec + ";\n"
                } else {
                    out = out + "    " + ms.retCtype + " _z; memset(&_z, 0, sizeof(_z)); return _z;\n"
                }
                out = out + "}\n"
                mi = mi + 1
            }
            out = out + "static const xc_" + ifn + "_vtable_t xc_" + ifn + "_cfg_vtable = {\n"
            mi = 0
            while mi < mn {
                let ms = methodSpecGet(is2.methList, mi)
                out = out + "    ." + ms.name + " = xc_" + ifn + "__" + ms.name + "_cfg,\n"
                mi = mi + 1
            }
            out = out + "};\n\n"
        }
        i = i + 1
    }
    return out
}

mapper genResolvers(prog: Program) -> String {
    let out = "/* === DI resolvers === */\n"
    let i = 0
    let n = ifaceSpecLen(prog.ifaces)
    while i < n {
        let is2 = ifaceSpecGet(prog.ifaces, i)
        let ifn = is2.name
        let cfgp = prog.configPathFor(ifn)
        if string_len(cfgp) > 0 {
            // config-backed: parse the file once, return a fat ptr over the tree
            let parse = "xstd_yaml_parse(_src" + ifn + ")"
            if cfgp.endsWith2(".json") { parse = "xstd_json_parse(_src" + ifn + ")" }
            out = out + "static xc_" + ifn + "_t xc_resolve_" + ifn + "(void) {\n"
            out = out + "    static xc_Json_t _cfg" + ifn + "; static bool _ci" + ifn + " = false;\n"
            out = out + "    if (!_ci" + ifn + ") { xc_string_t _src" + ifn + " = file_read_all(xc_string_from_cstr(\"" + cfgp + "\")); _cfg" + ifn + " = " + parse + "; _ci" + ifn + " = true; }\n"
            out = out + "    return (xc_" + ifn + "_t){ .self = (void*)_cfg" + ifn + ", .vtable = &xc_" + ifn + "_cfg_vtable };\n"
            out = out + "}\n\n"
            i = i + 1
        } else {
        out = out + "static xc_" + ifn + "_t xc_resolve_" + ifn + "(void) {\n"
        let chosen = chosenImpl(prog, ifn)
        if string_len(chosen) == 0 {
            out = out + "    xc_" + ifn + "_t _z; memset(&_z, 0, sizeof(_z)); return _z;\n"
        } else {
            if bindScopeFor(prog, ifn) == "singleton" {
                out = out + "    return xc_" + chosen + "_as_" + ifn + "(&xc_singleton_" + chosen + ");\n"
            } else {
                out = out + "    return xc_" + chosen + "_as_" + ifn + "(xc_new_" + chosen + "());\n"
            }
        }
        out = out + "}\n\n"
        i = i + 1
        }
    }
    return out + "\n"
}

mapper genSingletons(prog: Program) -> String {
    let out = "/* === Singleton storage === */\n"
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.scopeKind == "singleton" and string_len(b.configPath) == 0 {
                out = out + "static xc_" + b.concreteName + "_t xc_singleton_" + b.concreteName + ";\n"
                out = out + "static bool xc_singleton_" + b.concreteName + "_initialized = false;\n"
            }
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

mapper genSingletonInit(prog: Program) -> String {
    let out = "/* === Singleton init === */\n"
    out = out + "static void xc_init_singletons(void) {\n"
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            if b.scopeKind == "singleton" and string_len(b.configPath) == 0 {
                let cn = b.concreteName
                // xc_new_ wires deps; singletons capture stable &storage addresses,
                // so initialisation order is irrelevant.
                out = out + "    if (!xc_singleton_" + cn + "_initialized) {\n"
                out = out + "        xc_singleton_" + cn + "_initialized = true;\n"
                out = out + "        xc_singleton_" + cn + " = *xc_new_" + cn + "();\n"
                out = out + "    }\n"
            }
            j = j + 1
        }
        i = i + 1
    }
    out = out + "}\n\n"
    return out
}

mapper genFactories(prog: Program) -> String {
    let out = "/* === DI factory functions === */\n"
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        let j = 0
        let m = bindSpecLen(mod.bindings)
        while j < m {
            let b = bindSpecGet(mod.bindings, j)
            let ifn = b.ifaceName
            let cn = b.concreteName
            let mname = mod.name
            let retType = ""
            if isInterface(prog, ifn) {
                retType = "xc_" + ifn + "_t"
            } else {
                retType = "xc_" + cn + "_t*"
            }
            out = out + "static " + retType + " xc_" + mname + "_resolve_" + ifn + "(void) {\n"
            if b.scopeKind == "singleton" and string_len(b.configPath) == 0 {
                if isInterface(prog, ifn) {
                    out = out + "    return xc_" + cn + "_as_" + ifn + "(&xc_singleton_" + cn + ");\n"
                } else {
                    out = out + "    return &xc_singleton_" + cn + ";\n"
                }
            } else {
                // Transient: heap-allocate and wire deps
                out = out + "    xc_" + cn + "_t* _obj = (xc_" + cn + "_t*)malloc(sizeof(xc_" + cn + "_t));\n"
                out = out + "    if (!_obj) abort();\n"
                out = out + "    memset(_obj, 0, sizeof(xc_" + cn + "_t));\n"
                // Wire deps
                let cls = findClass(prog, cn)
                let di = 0
                let dn = depSpecLen(cls.depList)
                while di < dn {
                    let dep = depSpecGet(cls.depList, di)
                    let depConc = findBinding(prog, mname, dep.ifaceName)
                    let depScope = findScope(prog, mname, dep.ifaceName)
                    if string_len(depConc) > 0 {
                        if isInterface(prog, dep.ifaceName) {
                            if depScope == "singleton" {
                                out = out + "    _obj->" + dep.name + " = xc_" + depConc + "_as_" + dep.ifaceName + "(&xc_singleton_" + depConc + ");\n"
                            } else {
                                out = out + "    xc_" + depConc + "_t* _dep_" + dep.name + " = (xc_" + depConc + "_t*)malloc(sizeof(xc_" + depConc + "_t));\n"
                                out = out + "    memset(_dep_" + dep.name + ", 0, sizeof(xc_" + depConc + "_t));\n"
                                out = out + "    _obj->" + dep.name + " = xc_" + depConc + "_as_" + dep.ifaceName + "(_dep_" + dep.name + ");\n"
                            }
                        }
                    }
                    di = di + 1
                }
                if isInterface(prog, ifn) {
                    out = out + "    return xc_" + cn + "_as_" + ifn + "(_obj);\n"
                } else {
                    out = out + "    return _obj;\n"
                }
            }
            out = out + "}\n\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

