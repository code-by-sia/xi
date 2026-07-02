// xc parser — module / atom / machine declarations
// (part of the parser — spliced via the xc.xi manifest)

// Parse `module Name { bind ... }` (may contain its own `entry main`)
type ModuleResult = { spec: ModuleSpec, ps: PState, entry: FuncSpec, hasEntry: Bool }

mapper parseModule(ps: PState) -> ModuleResult {
    let ps2 = advance(ps)  // "module"
    let name = "App"
    if peek(ps2).kind != 102 {        // a name is present (not an anonymous `module {`)
        name = peek(ps2).text
        ps2 = advance(ps2)
    }
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }  // {

    let bindings: BindSpec[] = []
    let mId = ""
    let mTitle = ""
    let mDesc = ""
    let mVer = ""
    let mLic = ""
    let mIncludes: String[] = []    // unset -> file+imports only; set -> glob-gather
    let mExcludes: String[] = []
    let mDeps: String[] = []        // dependency archive URLs (xi install)
    let constNames: String[] = []   // module-scoped `const` values ("name:ctype")
    let constInit: Token[] = []     // tokens: `NAME = expr` per const
    let mEntry = FuncSpec {
        isCreator: false, isAsync: false, kind: "entry", name: "main",
        params: "xc_arr_string_t args", retCtype: "xc_integer_t",
        bodyTokens: [], hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
    }
    let mHasEntry = false
    while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
        // import, an inner `entry`, a bind, or a metadata field
        if peek(ps2).kind == 230 and peekAt(ps2, 1).kind == 219 {   // async entry
            let er = parseEntry(advance(ps2), true)
            mEntry = er.spec  mHasEntry = true  ps2 = er.ps
        } else {
        if peek(ps2).kind == 219 {                                  // entry
            let er = parseEntry(ps2, false)
            mEntry = er.spec  mHasEntry = true  ps2 = er.ps
        } else {
        if peek(ps2).kind == 244 {  // import
            ps2 = advance(ps2)
            ps2 = advance(ps2)  // skip module name
        } else {
            if peek(ps2).kind == 208 {  // bind
                ps2 = advance(ps2)
                // interface type name
                let ifName = peek(ps2).text
                let tr = parseTypeExpr(ps2)
                ps2 = tr.ps
                if peek(ps2).kind == 109 { ps2 = advance(ps2) }  // ->
                // binding target
                if peek(ps2).kind == 254 {  // none
                    ps2 = advance(ps2)
                } else {
                    if peek(ps2).kind == 104 {  // [list]
                        ps2 = skipBlock(ps2)
                    } else {
                    if peek(ps2).kind == 1 and peek(ps2).text == "readConfig" and peekAt(ps2, 1).kind == 100 {
                        // bind I -> readConfig("path") — config-backed implementor
                        let cp = ""
                        ps2 = advance(ps2)                                  // readConfig
                        if peek(ps2).kind == 100 { ps2 = advance(ps2) }    // (
                        if peek(ps2).kind == 4 { cp = peek(ps2).text  ps2 = advance(ps2) }
                        if peek(ps2).kind == 101 { ps2 = advance(ps2) }    // )
                        bindings = appendBindSpec(bindings, BindSpec {
                            ifaceName: ifName, concreteName: "", scopeKind: "singleton", configPath: cp
                        })
                    } else {
                        let concName = peek(ps2).text
                        ps2 = advance(ps2)
                        let scopeVal = "transient"
                        if peek(ps2).kind == 209 {  // as
                            ps2 = advance(ps2)
                            let scopeTok = peek(ps2)
                            if scopeTok.kind == 239 { scopeVal = "singleton" }
                            if scopeTok.kind == 240 { scopeVal = "transient" }
                            if scopeTok.kind == 241 { scopeVal = "scoped" }
                            ps2 = advance(ps2)
                        }
                        bindings = appendBindSpec(bindings, BindSpec {
                            ifaceName: ifName, concreteName: concName, scopeKind: scopeVal, configPath: ""
                        })
                    }
                    }
                }
            } else {
                // metadata field:  key = "value"   or   key = ["a", "b"]  — or a `const`
                let key = peek(ps2).text
                if key == "const" {
                    // const NAME: Type = expr   (referenced anywhere as Module.NAME)
                    ps2 = advance(ps2)   // const
                    let cname = peek(ps2).text
                    constInit = appendToken(constInit, peek(ps2))   // NAME
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 108 { ps2 = advance(ps2) }   // :
                    let ctr = parseTypeExpr(ps2)
                    ps2 = ctr.ps
                    constNames = appendString(constNames, cname + ":" + ctr.ctype)
                    if peek(ps2).kind == 111 {                        // =
                        constInit = appendToken(constInit, peek(ps2))
                        ps2 = advance(ps2)
                    }
                    // collect the value expression up to the next module-level item
                    let depth = 0
                    let coll = true
                    while coll {
                        let it = peek(ps2)
                        if it.kind == 0 { coll = false }
                        else {
                            let boundary = false
                            if depth == 0 {
                                if it.kind == 103 or it.kind == 208 or it.kind == 219 or it.kind == 230 or it.kind == 244 { boundary = true }
                                if it.kind == 1 and it.text == "const" { boundary = true }
                                if it.kind == 1 and peekAt(ps2, 1).kind == 111 { boundary = true }   // next `key =`
                            }
                            if boundary { coll = false }
                            else {
                                if it.kind == 100 or it.kind == 104 or it.kind == 102 { depth = depth + 1 }
                                if it.kind == 101 or it.kind == 105 or it.kind == 103 { depth = depth - 1 }
                                constInit = appendToken(constInit, it)
                                ps2 = advance(ps2)
                            }
                        }
                    }
                } else {
                if peekAt(ps2, 1).kind == 111 and peekAt(ps2, 2).kind == 104 {
                    // list value: includes / excludes
                    let items: String[] = []
                    ps2 = advance(advance(advance(ps2)))     // past key = [
                    while peek(ps2).kind != 105 and peek(ps2).kind != 0 {
                        if peek(ps2).kind == 4 { items = appendString(items, peek(ps2).text) }
                        ps2 = advance(ps2)
                    }
                    if peek(ps2).kind == 105 { ps2 = advance(ps2) }   // ]
                    if key == "includes" { mIncludes = items }
                    if key == "excludes" { mExcludes = items }
                    if key == "dependencies" { mDeps = items }
                } else {
                if peekAt(ps2, 1).kind == 111 {              // `=` "value"
                    let val = peekAt(ps2, 2).text
                    if key == "id"          { mId = val }
                    if key == "name"        { mTitle = val }
                    if key == "title"       { mTitle = val }
                    if key == "description" { mDesc = val }
                    if key == "version"     { mVer = val }
                    if key == "license"     { mLic = val }
                    ps2 = advance(advance(advance(ps2)))     // key = value
                } else {
                    ps2 = advance(ps2)
                }
                }
                }
            }
        }
        }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }  // }

    let spec = ModuleSpec {
        name: name, bindings: bindings,
        id: mId, title: mTitle, description: mDesc, version: mVer, license: mLic,
        includes: mIncludes, excludes: mExcludes, dependencies: mDeps,
        constNames: constNames, constInit: constInit
    }
    return ModuleResult { spec: spec, ps: ps2, entry: mEntry, hasEntry: mHasEntry }
}

// ── Program parser ────────────────────────────────────────────────

type AtomResult = { spec: AtomSpec, ps: PState }

// atom name { initial <expr>  (transition f(params) -> T { body })* }
mapper parseAtom(ps: PState) -> AtomResult {
    let ps2 = advance(ps)                 // consume 'atom'
    let name = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }   // {

    let initToks: Token[] = []
    let transitions: FuncSpec[] = []
    let running = true
    while running {
        let t = peek(ps2)
        if t.kind == 103 or t.kind == 0 {
            running = false
        } else {
            if t.kind == 291 {            // initial <expr>
                ps2 = advance(ps2)
                let d = 0
                let coll = true
                while coll {
                    let c = peek(ps2)
                    if c.kind == 0 { coll = false }
                    else {
                        if d == 0 and (c.kind == 290 or c.kind == 103) { coll = false }
                        else {
                            if c.kind == 100 or c.kind == 104 or c.kind == 102 { d = d + 1 }
                            if c.kind == 101 or c.kind == 105 or c.kind == 103 { d = d - 1 }
                            initToks = appendToken(initToks, c)
                            ps2 = advance(ps2)
                        }
                    }
                }
            } else {
                if t.kind == 290 {        // transition name(params) -> ret { body }
                    ps2 = advance(ps2)
                    let fnameTok = peek(ps2)
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 100 { ps2 = advance(ps2) }   // (
                    let pr = parseParams(ps2)
                    ps2 = pr.ps
                    if peek(ps2).kind == 101 { ps2 = advance(ps2) }   // )
                    let rr = parseRetType(ps2)
                    ps2 = rr.ps
                    let br = parseBody(ps2)
                    ps2 = br.ps
                    let fs = FuncSpec {
                        isCreator: false, isAsync: false, kind: "mapper",
                        name: name + "__" + fnameTok.text,
                        params: pr.params, retCtype: rr.ctype,
                        bodyTokens: br.bodyTokens,
                        hasWhere: false, whereTokens: [], fnDeps: [], topic: ""
                    }
                    transitions = appendFuncSpec(transitions, fs)
                } else {
                    ps2 = advance(ps2)
                }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }   // }

    let stateTypeName = ""
    if funcSpecLen(transitions) > 0 {
        stateTypeName = ctypeSuffix(funcSpecGet(transitions, 0).retCtype)
    } else {
        if tokenArrLen(initToks) > 0 { stateTypeName = tokenArrGet(initToks, 0).text }
    }
    let spec = AtomSpec {
        name: name, stateTypeName: stateTypeName,
        initToks: initToks, transitions: transitions
    }
    return AtomResult { spec: spec, ps: ps2 }
}

type MachineResult = { spec: MachineSpec, ps: PState }

// machine Name {
//   states A,B,C   initial A   [terminal X,Y | -]
//   [data { f: T = expr, ... }]
//   ( name[(params)] : From(,From)* -> To  [where <guard>]  [update { f: expr, ... }] )*
// }
mapper parseMachine(ps: PState) -> MachineResult {
    let ps2 = advance(ps)   // 'machine'
    let name = peek(ps2).text
    ps2 = advance(ps2)
    if peek(ps2).kind == 102 { ps2 = advance(ps2) }   // {

    let states: String[] = []
    let initial = ""
    let terminals: String[] = []
    let hasData = false
    let dataFields: String[] = []
    let dataInit: Token[] = []
    let transitions: MachineTransition[] = []

    let running = true
    while running {
        let t = peek(ps2)
        if t.kind == 103 or t.kind == 0 {
            running = false
        } else {
            if t.kind == 293 {                  // states A, B, C
                ps2 = advance(ps2)
                let more = true
                while more {
                    if peek(ps2).kind == 1 {
                        states = appendString(states, peek(ps2).text)
                        ps2 = advance(ps2)
                        if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { more = false }
                    } else { more = false }
                }
            } else {
            if t.kind == 291 {                  // initial X
                ps2 = advance(ps2)
                initial = peek(ps2).text
                ps2 = advance(ps2)
            } else {
            if t.kind == 294 {                  // terminal X, Y  |  terminal -
                ps2 = advance(ps2)
                if peek(ps2).kind == 119 { ps2 = advance(ps2) }   // '-' = none
                else {
                    let more = true
                    while more {
                        if peek(ps2).kind == 1 {
                            terminals = appendString(terminals, peek(ps2).text)
                            ps2 = advance(ps2)
                            if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { more = false }
                        } else { more = false }
                    }
                }
            } else {
            if t.kind == 1 and t.text == "data" and peekAt(ps2, 1).kind == 102 {
                // data { f: T = expr, ... }  — machine-wide context
                hasData = true
                ps2 = advance(ps2)   // data
                ps2 = advance(ps2)   // {
                while peek(ps2).kind != 103 and peek(ps2).kind != 0 {
                    let fname = peek(ps2).text
                    dataInit = appendToken(dataInit, peek(ps2))   // name
                    ps2 = advance(ps2)
                    if peek(ps2).kind == 108 { ps2 = advance(ps2) }   // :
                    let dtr = parseTypeExpr(ps2)
                    ps2 = dtr.ps
                    dataFields = appendString(dataFields, fname + ":" + dtr.ctype)
                    if peek(ps2).kind == 111 {                        // =
                        dataInit = appendToken(dataInit, peek(ps2))
                        ps2 = advance(ps2)
                    }
                    let depth = 0
                    let coll = true
                    while coll {
                        let it = peek(ps2)
                        if it.kind == 0 { coll = false }
                        else { if depth == 0 and (it.kind == 106 or it.kind == 103) { coll = false }
                        else {
                            if it.kind == 100 or it.kind == 104 or it.kind == 102 { depth = depth + 1 }
                            if it.kind == 101 or it.kind == 105 or it.kind == 103 { depth = depth - 1 }
                            dataInit = appendToken(dataInit, it)
                            ps2 = advance(ps2)
                        } }
                    }
                    if peek(ps2).kind == 106 {                        // ,
                        dataInit = appendToken(dataInit, peek(ps2))
                        ps2 = advance(ps2)
                    }
                }
                if peek(ps2).kind == 103 { ps2 = advance(ps2) }       // }
            } else {
            if t.kind == 1 {                    // transition: name[(params)] : From* -> To
                let tname = t.text
                ps2 = advance(ps2)
                let params = ""
                if peek(ps2).kind == 100 {       // (params)
                    ps2 = advance(ps2)
                    let pr = parseParams(ps2)
                    params = pr.params
                    ps2 = pr.ps
                    if peek(ps2).kind == 101 { ps2 = advance(ps2) }
                }
                if peek(ps2).kind == 108 { ps2 = advance(ps2) }   // :
                let froms = ""
                let more = true
                while more {
                    if peek(ps2).kind == 1 {
                        if string_len(froms) > 0 { froms = froms + "," }
                        froms = froms + peek(ps2).text
                        ps2 = advance(ps2)
                        if peek(ps2).kind == 106 { ps2 = advance(ps2) } else { more = false }
                    } else { more = false }
                }
                if peek(ps2).kind == 109 { ps2 = advance(ps2) }   // ->
                let toState = peek(ps2).text
                ps2 = advance(ps2)
                // optional `where <guard>` — spans lines while inside parens or
                // after an operator that still expects an operand, so a guard can
                // wrap naturally; ends at `update`, `}`, EOF, or a line break at a
                // complete point (the next transition).
                let hasGuard = false
                let guardTokens: Token[] = []
                if peek(ps2).kind == 242 {
                    hasGuard = true
                    ps2 = advance(ps2)
                    let gc = true
                    let depth = 0
                    while gc {
                        let gt = peek(ps2)
                        if gt.kind == 0 or gt.kind == 103 or gt.text == "update" {
                            gc = false
                        } else {
                            guardTokens = appendToken(guardTokens, gt)
                            if gt.kind == 100 { depth = depth + 1 }
                            if gt.kind == 101 { depth = depth - 1 }
                            ps2 = advance(ps2)
                            let nx = peek(ps2)
                            if nx.kind == 0 or nx.kind == 103 or nx.text == "update" {
                                gc = false
                            } else {
                                // Stop at a line break only when the expression is
                                // complete: not inside parens, and neither the line's
                                // last token nor the next line's first token is an
                                // operator awaiting an operand (so `a\n and b` and
                                // `a and\n b` both continue; a new transition, which
                                // starts with an identifier, stops).
                                if nx.line != gt.line and depth <= 0 and not expectsOperand(gt.kind) and not expectsOperand(nx.kind) {
                                    gc = false
                                }
                            }
                        }
                    }
                }
                // optional `update { f: expr, ... }`
                let hasUpdate = false
                let updateTokens: Token[] = []
                if peek(ps2).kind == 1 and peek(ps2).text == "update" and peekAt(ps2, 1).kind == 102 {
                    hasUpdate = true
                    ps2 = advance(ps2)   // update
                    ps2 = advance(ps2)   // {
                    let depth = 1
                    while depth > 0 and peek(ps2).kind != 0 {
                        let ut = peek(ps2)
                        if ut.kind == 102 { depth = depth + 1 }
                        if ut.kind == 103 { depth = depth - 1 }
                        if depth > 0 { updateTokens = appendToken(updateTokens, ut) }
                        ps2 = advance(ps2)
                    }
                }
                transitions = appendMachineTransition(transitions, MachineTransition {
                    name: tname, params: params, froms: froms, toState: toState,
                    hasGuard: hasGuard, guardTokens: guardTokens,
                    hasUpdate: hasUpdate, updateTokens: updateTokens
                })
            } else {
                ps2 = advance(ps2)
            }
            }
            }
            }
            }
        }
    }
    if peek(ps2).kind == 103 { ps2 = advance(ps2) }   // }

    let spec = MachineSpec {
        name: name, states: states, initial: initial, terminals: terminals,
        hasData: hasData, dataFields: dataFields, dataInit: dataInit,
        transitions: transitions
    }
    return MachineResult { spec: spec, ps: ps2 }
}

