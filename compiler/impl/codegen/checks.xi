// xc codegen — static validation: machine graphs + purity
// (part of the generator — spliced via the xc.xi manifest)

// Static validation of every `machine` graph. Unknown state references are
// errors; unreachable states and dead ends (a non-terminal state with no
// outgoing transition) are warnings.
consumer checkMachines(prog: Program) {
    let mi = 0
    let mn = machineSpecLen(prog.machines)
    while mi < mn {
        let m = machineSpecGet(prog.machines, mi)
        let trn = machineTransLen(m.transitions)
        if machineStateIndex(m, m.initial) < 0 {
            diag_error(0, "machine " + m.name + ": initial state '" + m.initial + "' is not declared")
        }
        let ti = 0
        while ti < stringArrLen(m.terminals) {
            let tnm = stringArrGet(m.terminals, ti)
            if machineStateIndex(m, tnm) < 0 {
                diag_error(0, "machine " + m.name + ": terminal '" + tnm + "' is not declared")
            }
            ti = ti + 1
        }
        // transition source/target states must exist
        let k = 0
        while k < trn {
            let tr = machineTransGet(m.transitions, k)
            if machineStateIndex(m, tr.toState) < 0 {
                diag_error(0, "machine " + m.name + ": transition '" + tr.name + "' targets unknown state '" + tr.toState + "'")
            }
            let fcsv = tr.froms
            let start = 0
            let i = 0
            let n = string_len(fcsv)
            while i <= n {
                let isSep = i == n
                if not isSep { if string_char_at(fcsv, i) == 44 { isSep = true } }
                if isSep {
                    let nm = string_slice(fcsv, start, i)
                    if string_len(nm) > 0 and machineStateIndex(m, nm) < 0 {
                        diag_error(0, "machine " + m.name + ": transition '" + tr.name + "' from unknown state '" + nm + "'")
                    }
                    start = i + 1
                }
                i = i + 1
            }
            k = k + 1
        }
        // reachability from the initial state (fixpoint over transitions)
        let reached: String[] = []
        reached = appendString(reached, m.initial)
        let changed = true
        while changed {
            changed = false
            let t = 0
            while t < trn {
                let tr = machineTransGet(m.transitions, t)
                if not strArrContains(reached, tr.toState) {
                    let fcsv = tr.froms
                    let start = 0
                    let i = 0
                    let n = string_len(fcsv)
                    let anyReached = false
                    while i <= n {
                        let isSep = i == n
                        if not isSep { if string_char_at(fcsv, i) == 44 { isSep = true } }
                        if isSep {
                            let nm = string_slice(fcsv, start, i)
                            if string_len(nm) > 0 and strArrContains(reached, nm) { anyReached = true }
                            start = i + 1
                        }
                        i = i + 1
                    }
                    if anyReached { reached = appendString(reached, tr.toState)  changed = true }
                }
                t = t + 1
            }
        }
        // warnings
        let si = 0
        let ns = stringArrLen(m.states)
        while si < ns {
            let st = stringArrGet(m.states, si)
            if not strArrContains(reached, st) {
                diag_warn(0, "machine " + m.name + ": state '" + st + "' is unreachable from '" + m.initial + "'")
            }
            if not strArrContains(m.terminals, st) {
                let hasOut = false
                let t2 = 0
                while t2 < trn {
                    if csvHasState(machineTransGet(m.transitions, t2).froms, st) { hasOut = true }
                    t2 = t2 + 1
                }
                if not hasOut {
                    diag_warn(0, "machine " + m.name + ": non-terminal state '" + st + "' has no outgoing transition (dead end)")
                }
            }
            si = si + 1
        }
        mi = mi + 1
    }
}

// ── Purity enforcement (Phase 2 of the memory-management plan) ──────────────
// A pure-kind function — mapper / predicate / projector — promises no observable
// side effects; that promise is exactly what lets the compiler pass its
// arguments by borrow (they cannot escape). We enforce it: a pure-kind body must
// not perform direct I/O (system.stdout/stderr/stdin) nor call an
// unambiguously-impure function (one whose *every* definition is a `consumer` or
// `action`). Notes on what is deliberately allowed:
//   - extern "C" functions are trusted at their declared kind and never count as
//     impure callees (we can't see their bodies; the FFI boundary is the author's
//     contract — e.g. diag_error/run_command).
//   - `producer` and `creator` are not treated as impure: `producer` is the
//     generic `() -> T` kind (often, but not always, pure — e.g. json.parse), and
//     `creator` only allocates a fresh value. Calling them is fine.
//   - an overloaded name with any non-(consumer/action) definition is not
//     flagged — conservative, so we never reject a legitimate pure call.

// Single switch for the diagnostic severity (warn while bootstrapping, error
// once the tree is known clean).
consumer diag_purity(line: Integer, msg: String) { diag_error(line, msg) }

predicate isPureKind(k: String) {
    return k == "mapper" or k == "predicate" or k == "projector"
}

// Names that are impure in *every* user definition (overloads with any other
// kind are excluded, so the rule is sound against false positives).
mapper collectImpureNames(prog: Program) -> String[] {
    let impure: String[] = []   // >=1 consumer/action definition
    let other:  String[] = []   // >=1 definition of any other kind
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let f = funcSpecGet(prog.functions, i)
        if f.kind == "consumer" or f.kind == "action" { impure = appendString(impure, f.name) }
        else { other = appendString(other, f.name) }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let mth = methodSpecGet(cs.methList, mi)
            if mth.kind == "consumer" or mth.kind == "action" { impure = appendString(impure, mth.name) }
            else { other = appendString(other, mth.name) }
            mi = mi + 1
        }
        ci = ci + 1
    }
    let out: String[] = []
    let k = 0
    let m = stringArrLen(impure)
    while k < m {
        let nm = stringArrGet(impure, k)
        if not strArrContains(other, nm) and not strArrContains(out, nm) {
            out = appendString(out, nm)
        }
        k = k + 1
    }
    return out
}

// Scan one pure-kind body's tokens for I/O and impure calls. String literals are
// single tokens, so names that appear only inside generated-code strings (as in
// codegen itself) never match — only real call sites do.
consumer scanPureBody(kind: String, fname: String, toks: Token[], impure: String[]) {
    let n = tokenArrLen(toks)
    let i = 0
    while i < n {
        let k = toks.kindAt(i)
        // direct I/O:  system . (stdout|stderr|stdin)
        if k == 1 and toks.textAt(i) == "system" and i + 2 < n and toks.kindAt(i + 1) == 107 {
            let f2 = toks.textAt(i + 2)
            if f2 == "stdout" or f2 == "stderr" or f2 == "stdin" {
                diag_purity(tokenArrGet(toks, i).line,
                    "pure " + kind + " '" + fname + "' must not perform I/O (system." + f2 + "); use a producer/consumer/action")
            }
        }
        // impure call:  IDENT (
        if k == 1 and i + 1 < n and toks.kindAt(i + 1) == 100 {
            let callee = toks.textAt(i)
            if callee != fname and strArrContains(impure, callee) {
                diag_purity(tokenArrGet(toks, i).line,
                    "pure " + kind + " '" + fname + "' must not call impure '" + callee + "'; make it a producer/consumer/action")
            }
        }
        i = i + 1
    }
}

consumer checkPurity(prog: Program) {
    let impure = collectImpureNames(prog)
    let i = 0
    let n = funcSpecLen(prog.functions)
    while i < n {
        let f = funcSpecGet(prog.functions, i)
        if isPureKind(f.kind) { scanPureBody(f.kind, f.name, f.bodyTokens, impure) }
        i = i + 1
    }
    let ci = 0
    let cn = classSpecLen(prog.classes)
    while ci < cn {
        let cs = classSpecGet(prog.classes, ci)
        let mi = 0
        let mn = methodSpecLen(cs.methList)
        while mi < mn {
            let mth = methodSpecGet(cs.methList, mi)
            if isPureKind(mth.kind) { scanPureBody(mth.kind, mth.name, mth.bodyTokens, impure) }
            mi = mi + 1
        }
        ci = ci + 1
    }
}
