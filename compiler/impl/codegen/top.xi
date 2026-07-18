// The source file path, so `assert` failures can report file:line.
mapper genSrcFileDef(srcPath: String) -> String {
    return "const char* xc_src_file = \"" + srcPath.cEscape() + "\";\n"
}

// `xi test` (XC_TEST=1) replaces the entry with a runner over the `test` cases:
// each runs isolated (a failed assert aborts that test, the rest continue),
// then a summary + nonzero exit on any failure.
mapper genTestRunner(prog: Program, srcPath: String) -> String {
    let out = genSrcFileDef(srcPath)
    let n = funcSpecLen(prog.tests)
    let i = 0
    while i < n {
        let t = funcSpecGet(prog.tests, i)
        out = out + hoistCatches(prog, t.bodyTokens, "test" + int_to_string(i))
        out = out + hoistParallel(prog, t.bodyTokens, "test" + int_to_string(i))
        out = out + hoistLambdas(prog, t.bodyTokens, "test" + int_to_string(i))
        out = out + "static void xc_test_body_" + int_to_string(i) + "(void) {\n"
        out = out + funcDepPrologue(prog, t.fnDeps)
        let ctx = (seedFuncDeps(prog.newCtx(), t.fnDeps)).withTag("test" + int_to_string(i))
        out = out + genBody2(t.bodyTokens, ctx)
        out = out + "}\n"
        i = i + 1
    }
    out = out + "/* === Test runner === */\n"
    out = out + "int main(int argc, char** argv) {\n"
    out = out + genRuntimeConfig(prog)
    out = out + "    xc_init_singletons();\n"
    out = out + "    xc_atoms_init();\n"
    let j = 0
    while j < n {
        let t = funcSpecGet(prog.tests, j)
        out = out + "    xc_test_run(\"" + t.name.cEscape() + "\", xc_test_body_" + int_to_string(j) + ");\n"
        j = j + 1
    }
    out = out + "    return xc_test_summary();\n"
    out = out + "}\n"
    return out
}

// Runtime limits a module declared (`maxRequestBytes` / `jsonMaxDepth`), applied
// at startup before anything serves. The environment variable of the same
// purpose still overrides these, so a deployment can retune without a rebuild.
// Module identity for std/monitor's /monitor/info (0=id, 1=name, 2=version).
// Emitted from the module metadata, which only the compiler knows.
mapper genModuleInfo(prog: Program) -> String {
    let id = ""
    let nm = ""
    let ver = ""
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        if string_len(mod.id) > 0 { id = mod.id }
        if string_len(mod.title) > 0 { nm = mod.title }
        if string_len(mod.version) > 0 { ver = mod.version }
        i = i + 1
    }
    return "/* === Module identity (std/monitor) === */\n"
         + "xc_string_t xstd_module_info(xc_integer_t which) {\n"
         + "    if (which == 0) return xc_string_from_cstr(\"" + id.cEscape() + "\");\n"
         + "    if (which == 1) return xc_string_from_cstr(\"" + nm.cEscape() + "\");\n"
         + "    if (which == 2) return xc_string_from_cstr(\"" + ver.cEscape() + "\");\n"
         + "    return xc_string_from_cstr(\"\");\n"
         + "}\n\n"
}

mapper genRuntimeConfig(prog: Program) -> String {
    let out = ""
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let mod = moduleSpecGet(prog.modules, i)
        if string_len(mod.maxRequest) > 0 {
            out = out + "    xstd_set_max_request(" + mod.maxRequest + ");\n"
        }
        if string_len(mod.jsonDepth) > 0 {
            out = out + "    xstd_set_json_max_depth(" + mod.jsonDepth + ");\n"
        }
        i = i + 1
    }
    return out
}

mapper genEntry(prog: Program, srcPath: String) -> String {
    let es = prog.entrySpec
    let capN = es.params.buildCapNames(es.fnDeps)
    let capX = es.params.buildCapXTypes(es.fnDeps)
    let out = genSrcFileDef(srcPath)
    out = out + hoistCatches(prog, es.bodyTokens, "entry")
    out = out + hoistParallel(prog, es.bodyTokens, "entry")
    out = out + hoistLambdas(prog, es.bodyTokens, "entry")
    out = out + prog.hoistDelays(es.bodyTokens, "entry", capN, capX)
    out = out + "/* === Entry point === */\n"
    out = out + "int main(int argc, char** argv) {\n"
    out = out + genRuntimeConfig(prog)
    out = out + "    xc_init_singletons();\n"
    out = out + "    xc_atoms_init();\n"
    if prog.webEnabled() { out = out + "    xc_web_init();\n" }
    out = out + "    xc_arr_string_t xc_args;\n"
    out = out + "    xc_args.len = (xc_size_t)argc;\n"
    out = out + "    xc_args.cap = (xc_size_t)argc;\n"
    out = out + "    xc_args.data = (xc_string_t*)malloc(argc * sizeof(xc_string_t));\n"
    out = out + "    for (int i = 0; i < argc; i++) xc_args.data[i] = xc_string_from_cstr(argv[i]);\n"
    out = out + funcDepPrologue(prog, es.fnDeps)
    let ctx = ((seedFuncDeps(prog.newCtx(), es.fnDeps)).withTag("entry")).withCaps(capN, capX)
    if string_len(es.params) > 0 {
        let pname = lastWord(es.params)
        out = out + "    xc_arr_string_t " + pname + " = xc_args;\n"
        ctx = ctx.addSym(pname, "arr_string")
    }
    out = out + captureDecls(es.bodyTokens)
    ctx = seedCaptures(ctx, es.bodyTokens)
    out = out + genBody2(es.bodyTokens, ctx)
    // scheduled jobs: register each, then run the cron scheduler (blocks forever)
    let sn = funcSpecLen(prog.scheduled)
    if sn > 0 {
        let s = 0
        while s < sn {
            let job = funcSpecGet(prog.scheduled, s)
            if job.topic.startsWith2("every:") {
                let everyMs = string_slice(job.topic, 6, string_len(job.topic))
                out = out + "    xstd_sched_register_interval((void(*)(void))xc_" + job.name + ", " + everyMs + ");\n"
            } else {
                out = out + "    xstd_sched_register((void(*)(void))xc_" + job.name + ", \"" + job.topic.cEscape() + "\");\n"
            }
            s = s + 1
        }
        out = out + "    xstd_scheduler_run();\n"
    }
    out = out + "    return 0;\n"
    out = out + "}\n"
    return out
}

// Array typedefs for user types — use xc_T_t* (pointer), so only the
// forward declaration of T is required. Emit BEFORE compound bodies.
mapper genArrTypedefs(prog: Program) -> String {
    let out = "/* === User array typedefs === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not isCompositeAlias(ts) {
            out = out + "typedef struct { xc_" + ts.name + "_t* data; xc_size_t len; xc_size_t cap; } xc_arr_" + ts.name + "_t;\n"
            out = out + "typedef xc_List_t xc_List_" + ts.name + "_t;\n"   // List<ts> / Vec<ts>
            if prog.usesQuery() { out = out + "typedef xc_QueryPlan_t xc_Query_" + ts.name + "_t;\n" }  // Query<ts>
            out = out + "typedef xc_Set_t xc_Set_" + ts.name + "_t;\n"     // Set<ts>
            out = out + "typedef xc_Stack_t xc_Stack_" + ts.name + "_t;\n" // Stack<ts>
            out = out + "typedef xc_Queue_t xc_Queue_" + ts.name + "_t;\n" // Queue<ts>
            out = out + "typedef xc_SortedQueue_t xc_SortedQueue_" + ts.name + "_t;\n"  // SortedQueue<ts>
            out = out + "typedef xc_Future_t xc_Future_" + ts.name + "_t;\n"  // Future<ts>
            // Map<primitive-key, ts> — one alias per primitive/String key type
            out = out + "typedef xc_Map_t xc_Map_integer_" + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_number_"  + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_bool_"    + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_string_"  + ts.name + "_t;\n"
            out = out + "typedef xc_Map_t xc_Map_char_"    + ts.name + "_t;\n"
        }
        i = i + 1
    }
    // Arrays of interface fat pointers (for list deps `I[]`)
    let j = 0
    let m = ifaceSpecLen(prog.ifaces)
    while j < m {
        let is2 = ifaceSpecGet(prog.ifaces, j)
        out = out + "typedef struct { xc_" + is2.name + "_t* data; xc_size_t len; xc_size_t cap; } xc_arr_" + is2.name + "_t;\n"
        j = j + 1
    }
    return out + "\n"
}

// Optional typedefs embed xc_T_t by value, so they require the full type
// definition. Emit AFTER compound bodies / refined aliases.
mapper genOptTypedefs(prog: Program) -> String {
    let out = "/* === User optional typedefs === */\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not isCompositeAlias(ts) {
            out = out + "typedef struct { bool has_value; xc_" + ts.name + "_t value; } xc_opt_" + ts.name + "_t;\n"
        }
        i = i + 1
    }
    return out + "\n"
}

// Result<T> typedefs: { bool ok; T value; xc_string_t err; }
// Emitted for primitives and every user type, so `T!` is always available.
mapper genResTypedefs(prog: Program) -> String {
    let out = "/* === Result typedefs (T!) === */\n"
    out = out + "typedef struct { bool ok; xc_number_t value;  xc_string_t err; } xc_res_number_t;\n"
    out = out + "typedef struct { bool ok; xc_integer_t value; xc_string_t err; } xc_res_integer_t;\n"
    out = out + "typedef struct { bool ok; xc_bool_t value;    xc_string_t err; } xc_res_bool_t;\n"
    out = out + "typedef struct { bool ok; xc_string_t value;  xc_string_t err; } xc_res_string_t;\n"
    out = out + "typedef struct { bool ok; xc_char_t value;    xc_string_t err; } xc_res_char_t;\n"
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if not isCompositeAlias(ts) {
            out = out + "typedef struct { bool ok; xc_" + ts.name + "_t value; xc_string_t err; } xc_res_" + ts.name + "_t;\n"
        }
        i = i + 1
    }
    return out + "\n"
}

// extern "C" declarations (bare names — these resolve to C helpers/runtime)
mapper genExternDecls(prog: Program) -> String {
    let out = "/* === Extern C declarations === */\n"
    let i = 0
    let n = funcSpecLen(prog.externs)
    while i < n {
        let fs = funcSpecGet(prog.externs, i)
        out = out + "extern " + fs.retCtype + " " + fs.name + "(" + fs.params + ");\n"
        i = i + 1
    }
    return out + "\n"
}

// Forward declarations for all free functions and creators.
mapper genFuncForwardDecls(prog: Program) -> String {
    let out = "/* === Function forward declarations === */\n"
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let fs = funcSpecGet(prog.functions, i)
        let isAsync = fs.isAsync
        let retC = fs.retCtype
        if isAsync { retC = fs.asyncInnerCtype() }
        out = out + "static " + cTy(retC) + " xc_" + fs.name + "(" + cSig(fs.params) + ");\n"
        if isAsync { out = out + "static xc_Future_t xc_spawn_" + fs.name + "(" + cSig(fs.params) + ");\n" }
        i = i + 1
    }
    let s = 0
    let sn = funcSpecLen(prog.scheduled)
    while s < sn {
        out = out + "static void xc_" + funcSpecGet(prog.scheduled, s).name + "(void);\n"
        s = s + 1
    }
    return out + "\n"
}

mapper genHeader() -> String => "/* Generated by xc-bootstrap — X compiler written in X */\n#include \"runtime.h\"\n\n"

// Assign each `interrupt` type an integer id used for runtime handler matching.
mapper genInterruptDefs(prog: Program) -> String {
    let n = stringArrLen(prog.interrupts)
    if n == 0 { return "" }
    let out = "/* === Interrupt type ids === */\n"
    let i = 0
    while i < n {
        out = out + "#define XC_INT_" + stringArrGet(prog.interrupts, i) + " " + int_to_string(i) + "\n"
        i = i + 1
    }
    return out + "\n"
}

// Atom holders + transition prototypes (emitted before any use site).
mapper genAtomDecls(prog: Program) -> String {
    let out = "/* === Atom holders & transition prototypes === */\n"
    let i = 0
    let n = atomSpecLen(prog.atoms)
    while i < n {
        let a = atomSpecGet(prog.atoms, i)
        let st = "xc_" + a.stateTypeName + "_t"
        out = out + "static " + st + " __atom_" + a.name + ";\n"
        // Bounded history for undo()/time-travel (keeps the most recent states).
        out = out + "static " + st + " __atom_" + a.name + "_hist[256];\n"
        out = out + "static int __atom_" + a.name + "_histlen = 0;\n"
        out = out + "static void xc_atom_" + a.name + "_push(void) {\n"
        out = out + "    if (__atom_" + a.name + "_histlen == 256) { memmove(__atom_" + a.name + "_hist, __atom_" + a.name + "_hist + 1, 255 * sizeof(" + st + ")); __atom_" + a.name + "_histlen = 255; }\n"
        out = out + "    __atom_" + a.name + "_hist[__atom_" + a.name + "_histlen++] = __atom_" + a.name + ";\n}\n"
        out = out + "static " + st + " xc_atom_" + a.name + "_undo(void) {\n"
        out = out + "    if (__atom_" + a.name + "_histlen > 0) __atom_" + a.name + " = __atom_" + a.name + "_hist[--__atom_" + a.name + "_histlen];\n"
        out = out + "    return __atom_" + a.name + ";\n}\n"
        let j = 0
        let m = funcSpecLen(a.transitions)
        while j < m {
            let fs = funcSpecGet(a.transitions, j)
            out = out + "static " + cTy(fs.retCtype) + " xc_" + fs.name + "(" + cSig(fs.params) + ");\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// Atom transition bodies + the runtime initializer that seeds each holder.
mapper genAtomDefs(prog: Program) -> String {
    let out = "/* === Atom transitions === */\n"
    let i = 0
    let n = atomSpecLen(prog.atoms)
    while i < n {
        let a = atomSpecGet(prog.atoms, i)
        let j = 0
        let m = funcSpecLen(a.transitions)
        while j < m {
            out = out + emitOneFunc(prog, funcSpecGet(a.transitions, j))
            j = j + 1
        }
        i = i + 1
    }
    out = out + "static void xc_atoms_init(void) {\n"
    let k = 0
    while k < n {
        let a = atomSpecGet(prog.atoms, k)
        let e = genExpr(a.initToks, 0, prog.newCtx())
        out = out + "    __atom_" + a.name + " = " + e.code + ";\n"
        k = k + 1
    }
    return out + "}\n\n"
}

// Signature suffix after `self` for a transition's params ("" or ", <params>").
mapper machineSig(params: String) -> String {
    if string_len(params) > 0 { return ", " + params }
    return ""
}

// The legality condition for a transition: source-state match (&& guard).
mapper machineCond(prog: Program, m: MachineSpec, tr: MachineTransition) -> String {
    let cond = m.stateCond(tr.froms)
    if tr.hasGuard {
        let gctx = prog.newCtx().seedParams(tr.params)
        if m.hasData { gctx = gctx.addSym("data", m.name + "Data") }
        cond = "(" + cond + ") && (" + genExpr(tr.guardTokens, 0, gctx).code + ")"
    }
    return cond
}

// Machine function prototypes (so use sites resolve regardless of order).
mapper genMachineDecls(prog: Program) -> String {
    let out = "/* === Machine function prototypes === */\n"
    let i = 0
    let n = machineSpecLen(prog.machines)
    while i < n {
        let m = machineSpecGet(prog.machines, i)
        let mn = m.name
        out = out + "static xc_" + mn + "_t xc_" + mn + "__start(void);\n"
        out = out + "static xc_string_t xc_" + mn + "__state(xc_" + mn + "_t self);\n"
        out = out + "static xc_bool_t xc_" + mn + "__isTerminal(xc_" + mn + "_t self);\n"
        let j = 0
        let tn = machineTransLen(m.transitions)
        while j < tn {
            let tr = machineTransGet(m.transitions, j)
            let sig = machineSig(tr.params)
            out = out + "static xc_" + mn + "_t xc_" + mn + "__" + tr.name + "(xc_" + mn + "_t self" + sig + ");\n"
            out = out + "static xc_bool_t xc_" + mn + "__can_" + tr.name + "(xc_" + mn + "_t self" + sig + ");\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// Machine implementations: start (seeds state + data), state-name, isTerminal,
// and per transition a guarded mover + a `can` predicate. Illegal moves (wrong
// source state or failed guard) signal IllegalTransition.
mapper genMachineDefs(prog: Program) -> String {
    let out = "/* === Machine implementations === */\n"
    let i = 0
    let n = machineSpecLen(prog.machines)
    while i < n {
        let m = machineSpecGet(prog.machines, i)
        let mn = m.name
        // start(): initial state + data initial values
        out = out + "static xc_" + mn + "_t xc_" + mn + "__start(void) {\n"
            + "    xc_" + mn + "_t __r; __r.__state = " + int_to_string(m.stateIndex(m.initial)) + ";\n"
        if m.hasData {
            let di = m.dataInit
            let dp = 0
            let ictx = prog.newCtx()
            while di.kindAt(dp) != 0 {
                let fname = di.textAt(dp)
                dp = dp + 1
                if di.kindAt(dp) == 111 { dp = dp + 1 }   // =
                let e = genExpr(di, dp, ictx)
                dp = e.pos
                out = out + "    __r.data." + fname + " = " + m.castEmptyArr(fname, e) + ";\n"
                if di.kindAt(dp) == 106 { dp = dp + 1 }   // ,
            }
        }
        out = out + "    return __r;\n}\n"
        // state(): tag -> name
        out = out + "static xc_string_t xc_" + mn + "__state(xc_" + mn + "_t self) {\n"
        let si = 0
        let sn = stringArrLen(m.states)
        while si < sn {
            out = out + "    if (self.__state == " + int_to_string(si) + ") return xc_string_from_cstr(\"" + stringArrGet(m.states, si) + "\");\n"
            si = si + 1
        }
        out = out + "    return xc_string_from_cstr(\"?\");\n}\n"
        // isTerminal()
        let tcsv = ""
        let ti = 0
        let ttn = stringArrLen(m.terminals)
        while ti < ttn {
            if string_len(tcsv) > 0 { tcsv = tcsv + "," }
            tcsv = tcsv + stringArrGet(m.terminals, ti)
            ti = ti + 1
        }
        let tcond = "0"
        if string_len(tcsv) > 0 { tcond = m.stateCond(tcsv) }
        out = out + "static xc_bool_t xc_" + mn + "__isTerminal(xc_" + mn + "_t self) { return " + tcond + "; }\n"
        // a data-local declaration reused by guard/update bodies
        let dataLocal = ""
        if m.hasData { dataLocal = "    xc_" + mn + "Data_t data = self.data; (void)data;\n" }
        let j = 0
        let jn = machineTransLen(m.transitions)
        while j < jn {
            let tr = machineTransGet(m.transitions, j)
            let sig = machineSig(tr.params)
            let cond = machineCond(prog, m, tr)
            let toIdx = int_to_string(m.stateIndex(tr.toState))
            // update assignments (over the OLD data local; written to __r.data)
            let upd = ""
            if tr.hasUpdate {
                let ut = tr.updateTokens
                let up = 0
                let uctx = prog.newCtx().seedParams(tr.params)
                if m.hasData { uctx = uctx.addSym("data", mn + "Data") }
                while ut.kindAt(up) != 0 {
                    let fname = ut.textAt(up)
                    up = up + 1
                    if ut.kindAt(up) == 108 { up = up + 1 }   // :
                    let e = genExpr(ut, up, uctx)
                    up = e.pos
                    upd = upd + "        __r.data." + fname + " = " + m.castEmptyArr(fname, e) + ";\n"
                    if ut.kindAt(up) == 106 { up = up + 1 }   // ,
                }
            }
            // the mover
            out = out + "static xc_" + mn + "_t xc_" + mn + "__" + tr.name + "(xc_" + mn + "_t self" + sig + ") {\n"
                + dataLocal
                + "    if (" + cond + ") { xc_" + mn + "_t __r = self; __r.__state = " + toIdx + ";\n"
                + upd
                + "        return __r; }\n"
                + "    { xc_IllegalTransition_t __pl; __pl.from = xc_" + mn + "__state(self); __pl.to = xc_string_from_cstr(\"" + tr.toState + "\");\n"
                + "      xc_handler_t* __hh = xc_int_find(XC_INT_IllegalTransition);\n"
                + "      if (__hh == ((void*)0)) xc_int_unhandled(\"IllegalTransition\");\n"
                + "      if (!__hh->fn(&__pl)) longjmp(__hh->unwind, 1); }\n"
                + "    return self;\n}\n"
            // the can predicate
            out = out + "static xc_bool_t xc_" + mn + "__can_" + tr.name + "(xc_" + mn + "_t self" + sig + ") {\n"
                + dataLocal
                + "    return (" + cond + ");\n}\n"
            j = j + 1
        }
        i = i + 1
    }
    return out + "\n"
}

// FFI build metadata from `extern "C"` directives: emit each `include "..."`
// as a real `#include`, plus a `/* XC-BUILD-FLAGS: ... */` marker that compile_c
// scans to extend the cc command line (link libs, -I/-L, pkg-config names).
mapper genBuildMeta(prog: Program) -> String {
    let out = ""
    let nf = stringArrLen(prog.cFlags)
    if nf > 0 {
        let flags = ""
        let i = 0
        while i < nf {
            if i > 0 { flags = flags + " " }
            flags = flags + stringArrGet(prog.cFlags, i)
            i = i + 1
        }
        out = out + "/* XC-BUILD-FLAGS: " + flags + " */\n"
    }
    let ni = stringArrLen(prog.cIncludes)
    let j = 0
    while j < ni {
        out = out + "#include " + stringArrGet(prog.cIncludes, j) + "\n"
        j = j + 1
    }
    if string_len(out) > 0 { out = out + "\n" }
    return out
}

mapper genAll(prog: Program, srcPath: String, codecs: Codecs) -> String {
    let tail = genEntry(prog, srcPath)
    if prog.inTestMode() and funcSpecLen(prog.tests) > 0 { tail = genTestRunner(prog, srcPath) }
    return genHeader()
         + genBuildMeta(prog)
         + genInterruptDefs(prog)
         + genForwardDecls(prog)
         + genRefinedTypedefs(prog)
         + genArrTypedefs(prog)
         + genAliasTypedefs(prog)
         + genCompoundBodies(prog)
         + genSumBoxHelpers(prog)
         + genOptTypedefs(prog)
         + genResTypedefs(prog)
         + codecs.genEventCodecs(prog)
         + genExternDecls(prog)
         + genIfaceDecls(prog)
         + genClassStructs(prog)
         + genIfaceDefaults(prog)
         + genVtablesAndCasters(prog)
         + genCheckFns(prog)
         + genModuleConsts(prog)
         + genModuleInfo(prog)
         + genSingletons(prog)
         + genCtorResolverFwd(prog)
         + genSingletonAccessors(prog)
         + genMachineDecls(prog)
         + genConstructors(prog)
         + genConfigImpls(prog)
         + genResolvers(prog)
         + genSingletonInit(prog)
         + genFuncForwardDecls(prog)
         + codecs.genEventFwd(prog)
         + genAtomDecls(prog)
         + genFreeFunctions(prog)
         + genDecisionTables(prog)
         + genAtomDefs(prog)
         + genMachineDefs(prog)
         + genClassMethods(prog)
         + codecs.genEventDispatch(prog)
         + codecs.genWebDispatch(prog)
         + tail
}

