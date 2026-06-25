// xc parser — top-level parseProgram driver
// (part of the parser — spliced via the xc.xi manifest)

creator parseProgram(tokens: Token[]) -> Program {
    let ps = mkPState(tokens)

    let types: TypeSpec[] = []
    let ifaces: IfaceSpec[] = []
    let classes: ClassSpec[] = []
    let modules: ModuleSpec[] = []
    let functions: FuncSpec[] = []
    let externs: FuncSpec[] = []
    let interrupts: String[] = []
    let atoms: AtomSpec[] = []
    let machines: MachineSpec[] = []
    let eventTypes: String[] = []
    let tables: DecisionTable[] = []
    let tests: FuncSpec[] = []
    let scheduled: FuncSpec[] = []
    let libraries: ModuleSpec[] = []
    let infixFns: String[] = []
    let cIncludes: String[] = []
    let cFlags: String[] = []
    let entrySpec = FuncSpec {
        isCreator: false, isAsync: false,
        kind: "entry", name: "main",
        params: "xc_arr_string_t args",
        retCtype: "xc_integer_t",
        bodyTokens: [], hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
    }

    let running = true
    while running and peek(ps).kind != 0 {
        let t = peek(ps)

        // extern "C" { sig* } — collect signatures so we can emit C externs
        if t.kind == 235 {  // extern
            ps = advance(ps)
            if peek(ps).kind == 4 { ps = advance(ps) }   // string "C"
            if peek(ps).kind == 102 { ps = advance(ps) } // {
            while peek(ps).kind != 103 and peek(ps).kind != 0 {
              // Build directives: include/link/pkg/cflags/ldflags "value"
              let dt = peek(ps)
              let nx = peek(advance(ps))
              if dt.kind == 1 and nx.kind == 4 and (dt.text == "include" or dt.text == "link" or dt.text == "pkg" or dt.text == "cflags" or dt.text == "ldflags") {
                let val = nx.text
                if dt.text == "include" {
                    let pfx = string_slice(val, 0, 1)
                    if pfx == "<" or pfx == "\"" { cIncludes = appendString(cIncludes, val) }
                    else { cIncludes = appendString(cIncludes, "<" + val + ">") }
                } else {
                if dt.text == "link"  { cFlags = appendString(cFlags, "-l" + val) }
                else { if dt.text == "pkg" { cFlags = appendString(cFlags, "pkg:" + val) }
                else { cFlags = appendString(cFlags, val) } }   // cflags / ldflags: raw
                }
                ps = advance(advance(ps))
              } else {
                let isA = false
                if peek(ps).kind == 230 {
                    isA = true
                    ps = advance(ps)
                }
                let kr = parseFuncKind(ps)
                if kr.ok {
                    let nameTok = peek(kr.ps)
                    let ps3 = advance(kr.ps)
                    if peek(ps3).kind == 100 { ps3 = advance(ps3) }
                    let pr = parseParams(ps3)
                    ps3 = pr.ps
                    if peek(ps3).kind == 101 { ps3 = advance(ps3) }
                    let rr = parseRetType(ps3)
                    ps3 = rr.ps
                    let ec = FuncSpec {
                        isCreator: false, isAsync: isA, kind: kr.kind,
                        name: nameTok.text, params: pr.params,
                        retCtype: retCtypeFor(kr.kind, rr.ctype), bodyTokens: [],
                        hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
                    }
                    externs = appendFuncSpec(externs, ec)
                    ps = ps3
                } else {
                    ps = advance(ps)
                }
              }
            }
            if peek(ps).kind == 103 { ps = advance(ps) } // }
        } else {
            // type / interrupt / state declaration. `interrupt` is a compound
            // type that also gets an id; `state` is a compound type (an atom's
            // immutable value type).
            if t.kind == 200 or t.kind == 280 or t.kind == 289 or t.kind == 296 {
                let r = parseTypeDecl(ps)
                types = appendTypeSpec(types, r.spec)
                if t.kind == 280 { interrupts = appendString(interrupts, r.spec.name) }
                if t.kind == 296 { eventTypes = appendString(eventTypes, r.spec.name) }
                ps = r.ps
            } else {
            if t.kind == 288 {                          // atom declaration
                let ar = parseAtom(ps)
                atoms = appendAtomSpec(atoms, ar.spec)
                ps = ar.ps
            } else {
            if t.kind == 292 {                          // machine declaration
                let mr = parseMachine(ps)
                machines = appendMachineSpec(machines, mr.spec)
                // the machine's value type: { __state: Integer [, data: <M>Data] }
                // (build fields on the heap via appendString — literals would dangle).
                let mfields: String[] = []
                mfields = appendString(mfields, "__state:xc_integer_t")
                if mr.spec.hasData {
                    // the data context as a nested struct, so `m.data.field` works.
                    types = appendTypeSpec(types, TypeSpec {
                        name: mr.spec.name + "Data", isCompound: true, baseCtype: "",
                        fields: mr.spec.dataFields,
                        hasWhere: false, whereSrc: "", whereTokens: [],
                        isSum: false, variants: []
                    })
                    mfields = appendString(mfields, "data:xc_" + mr.spec.name + "Data_t")
                }
                types = appendTypeSpec(types, TypeSpec {
                    name: mr.spec.name, isCompound: true, baseCtype: "",
                    fields: mfields,
                    hasWhere: false, whereSrc: "", whereTokens: [],
                    isSum: false, variants: []
                })
                // register the IllegalTransition interrupt once
                let hasIT = false
                let ii = 0
                while ii < stringArrLen(interrupts) {
                    if stringArrGet(interrupts, ii) == "IllegalTransition" { hasIT = true }
                    ii = ii + 1
                }
                if not hasIT {
                    let itfields: String[] = []
                    itfields = appendString(itfields, "from:xc_string_t")
                    itfields = appendString(itfields, "to:xc_string_t")
                    types = appendTypeSpec(types, TypeSpec {
                        name: "IllegalTransition", isCompound: true, baseCtype: "",
                        fields: itfields,
                        hasWhere: false, whereSrc: "", whereTokens: [],
                        isSum: false, variants: []
                    })
                    interrupts = appendString(interrupts, "IllegalTransition")
                }
                ps = mr.ps
            } else {
                // interface
                if t.kind == 201 {
                    let r = parseIface(ps)
                    ifaces = appendIfaceSpec(ifaces, r.spec)
                    ps = r.ps
                } else {
                    // class
                    if t.kind == 202 {
                        let r = parseClass(ps)
                        classes = appendClassSpec(classes, r.spec)
                        ps = r.ps
                    } else {
                        // module
                        if t.kind == 210 {
                            let r = parseModule(ps)
                            modules = appendModuleSpec(modules, r.spec)
                            if r.hasEntry { entrySpec = r.entry }   // entry declared inside the module
                            ps = r.ps
                        } else {
                        if t.kind == 1 and t.text == "library" {
                            // library { id = "..." version = "..." includes = [...] }
                            // metadata only; inert in codegen, read by `xi pack`.
                            let r = parseModule(ps)
                            libraries = appendModuleSpec(libraries, r.spec)
                            ps = r.ps
                        } else {
                        if t.kind == 1 and t.text == "scheduled" {
                            // scheduled (deps) name() cron "<expr>" { body }
                            ps = advance(ps)                       // 'scheduled'
                            let sdeps: DepSpec[] = []
                            if peek(ps).kind == 100 {              // (deps)
                                ps = advance(ps)
                                while peek(ps).kind != 101 and peek(ps).kind != 0 {
                                    let dr = parseDep(ps)
                                    sdeps = appendDepSpec(sdeps, dr.spec)
                                    ps = dr.ps
                                }
                                if peek(ps).kind == 101 { ps = advance(ps) }
                            }
                            let sname = peek(ps).text              // job name
                            ps = advance(ps)
                            if peek(ps).kind == 100 { ps = advance(ps) }   // (
                            if peek(ps).kind == 101 { ps = advance(ps) }   // )
                            if peek(ps).text == "cron" { ps = advance(ps) } // 'cron'
                            let scron = peek(ps).text              // cron string literal
                            ps = advance(ps)
                            let sb = parseBody(ps)
                            ps = sb.ps
                            scheduled = appendFuncSpec(scheduled, FuncSpec {
                                isCreator: false, isAsync: false,
                                kind: "action", name: sname,
                                params: "", retCtype: "void",
                                bodyTokens: sb.bodyTokens,
                                hasWhere: false, whereTokens: [], fnDeps: sdeps, topic: scron
                            })
                        } else {
                            // `infix` modifier (a 2-arg function callable as `a f b`)
                            let isInfix = false
                            if t.kind == 1 and t.text == "infix" {
                                isInfix = true
                                ps = advance(ps)
                            }
                            // async prefix
                            let isAsync = false
                            if peek(ps).kind == 230 {
                                isAsync = true
                                ps = advance(ps)
                            }

                            // test "name" (deps?) { body }
                            if peek(ps).kind == 299 {
                                ps = advance(ps)  // test keyword
                                let testName = peek(ps).text   // string label
                                ps = advance(ps)
                                let tdeps: DepSpec[] = []
                                if peek(ps).kind == 100 {      // (deps)
                                    ps = advance(ps)
                                    while peek(ps).kind != 101 and peek(ps).kind != 0 {
                                        let dr = parseDep(ps)
                                        tdeps = appendDepSpec(tdeps, dr.spec)
                                        ps = dr.ps
                                    }
                                    if peek(ps).kind == 101 { ps = advance(ps) }
                                }
                                let tb = parseBody(ps)
                                ps = tb.ps
                                tests = appendFuncSpec(tests, FuncSpec {
                                    isCreator: false, isAsync: isAsync,
                                    kind: "test", name: testName,
                                    params: "", retCtype: "void",
                                    bodyTokens: tb.bodyTokens,
                                    hasWhere: false, whereTokens: [], fnDeps: tdeps, topic: ""
                                })
                            } else {
                            // entry  (top-level form)
                            if peek(ps).kind == 219 {
                                let er = parseEntry(ps, isAsync)
                                entrySpec = er.spec
                                ps = er.ps
                            } else {
                                // creator or function kind
                                if peek(ps).kind == 212 {
                                    let fr = parseFunc(ps, isAsync, true)
                                    functions = appendFuncSpec(functions, fr.spec)
                                    if isInfix { infixFns = appendString(infixFns, fr.spec.name) }
                                    ps = fr.ps
                                } else {
                                    if parseFuncKindCheck(ps) {
                                        let fr = parseFunc(ps, isAsync, false)
                                        functions = appendFuncSpec(functions, fr.spec)
                                        if isInfix { infixFns = appendString(infixFns, fr.spec.name) }
                                        if fr.hasTable { tables = appendDecisionTable(tables, fr.table) }
                                        if fr.hasOutType { types = appendTypeSpec(types, fr.outType) }
                                        ps = fr.ps
                                    } else {
                                        ps = advance(ps)
                                    }
                                }
                            }
                            }
                        }
                        }
                        }
                    }
                }
            }
            }
            }
        }
    }

    return Program {
        types: types, ifaces: ifaces, classes: classes,
        modules: modules, functions: functions, externs: externs,
        entrySpec: entrySpec, interrupts: interrupts, atoms: atoms,
        machines: machines, eventTypes: eventTypes, tables: tables,
        tests: tests, scheduled: scheduled, libraries: libraries, infixFns: infixFns,
        cIncludes: cIncludes, cFlags: cFlags
    }
}

decision parseFuncKindCheck(ps: PState) -> Bool {
    when peek(ps).kind == 213 => true
    when peek(ps).kind == 214 => true
    when peek(ps).kind == 215 => true
    when peek(ps).kind == 216 => true
    when peek(ps).kind == 217 => true
    when peek(ps).kind == 218 => true
    when peek(ps).kind == 256 => true   // decision
    else                      => false
}

