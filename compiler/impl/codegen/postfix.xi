// xc codegen — postfix/operator precedence chain (postfix .. expr)
// (part of the xc code generator — Program -> C99; spliced via codegen.xi)

mapper genPostfix(toks: Token[], pos: Integer, ctx: GCtx) -> ExprRes {
    let base = genPrimary(toks, pos, ctx)
    let code = base.code
    let typ = base.xtyp
    let bname = base.code
    let p = base.pos
    let cont = true
    while cont {
        let k = toks.kindAt(p)
        // extension function call: recv.method(args) -> xc_<key>__<method>(recv, args).
        // `key` is the receiver xtype, normalizing an array literal's `X[]` form to
        // the `arr_X` form array params/returns carry (and that the parser keys on).
        let extKey = typ
        if typ.endsWith2("[]") { extKey = "arr_" + string_slice(typ, 0, string_len(typ) - 2) }
        if (k == 107 or k == 129) and toks.kindAt(p + 2) == 100 and (ctx.prog).isFuncNameC(extKey + "__" + toks.textAt(p + 1)) {
            let ext = extKey + "__" + toks.textAt(p + 1)
            let al = genArgs(toks, p + 2, ctx)
            let callArgs = code
            if string_len(al.code) > 0 { callArgs = code + ", " + al.code }
            code = "xc_" + ext + "(" + callArgs + ")"
            typ = (ctx.prog).funcRetXType(ext)
            p = al.pos
            continue
        }
        if k == 107 or k == 129 {
            let fld = toks.textAt(p + 1)
            if typ.isListXType() and fld == "asSequence" {
                let fr = genSequenceChain(toks, p, code, typ.listElemXName(), ctx, false, "", "", "")
                code = fr.code
                typ = fr.xtyp
                p = fr.pos
            } else {
            if typ.isListXType() and isListFunc(fld) {
                let fr = genListFunc(toks, p, code, typ, fld, ctx)
                code = fr.code
                typ = fr.xtyp
                p = fr.pos
            } else {
            if toks.kindAt(p + 2) == 100 {
                if typ == "events:" {
                    // Built-in event facility (over the type-erased envelope).
                    let al = genArgs(toks, p + 2, ctx)
                    if fld == "dispatch" { code = "xc_event_dispatch(" + al.code + ")"  typ = "" }
                    if fld == "encode"   { code = "xc_event_encode(" + al.code + ")"    typ = "Json" }
                    if fld == "decode"   { code = "xc_event_decode(" + al.code + ")"    typ = "Event" }
                    if fld == "topic"    { code = "xstd_event_topic(" + al.code + ")"   typ = "String" }
                    if fld == "type"     { code = "xstd_event_type(" + al.code + ")"    typ = "String" }
                    if fld == "run"      { code = "xc_events_run()"  typ = "" }
                    if fld == "runAsync" { code = "xc_events_run_async()"  typ = "Thread" }
                    if fld == "stop"     { code = "xstd_eventq_close()"    typ = "" }
                    p = al.pos
                } else {
                if typ == "thread:" {
                    // Built-in thread facility: thread.channel() / thread.stopped()
                    let al = genArgs(toks, p + 2, ctx)
                    if fld == "channel" { code = "xstd_chan_new()"        typ = "Channel" }
                    if fld == "stopped" { code = "xstd_thread_stopped()"  typ = "Bool" }
                    p = al.pos
                } else {
                if typ == "Channel" {
                    let recv = code
                    if fld == "send" {
                        // ch.send(x): String passes through; a structured value
                        // (event/compound) is JSON-serialized; primitives stringify.
                        let dtoE = genExpr(toks, p + 3, ctx)
                        let payload = dtoE.code   // String / unknown: send as-is
                        if (ctx.prog).hasCodec(dtoE.xtyp) {
                            payload = "xstd_json_stringify(xc_tojson_" + dtoE.xtyp + "(" + dtoE.code + "))"
                        } else {
                            if dtoE.xtyp == "Integer" or dtoE.xtyp == "Number" or dtoE.xtyp == "Bool" {
                                payload = toStrC(dtoE.code, dtoE.xtyp)
                            }
                        }
                        code = "xstd_chan_send(" + recv + ", " + payload + ")"
                        typ = ""
                        p = dtoE.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }   // )
                    } else {
                    if fld == "recv" {
                        if toks.kindAt(p + 3) == 101 {
                            // ch.recv() -> raw String
                            code = "xstd_chan_recv(" + recv + ")"
                            typ = "String"
                            p = p + 4
                        } else {
                            // ch.recv(T) -> deserialize a structured T from JSON
                            let tn = toks.textAt(p + 3)
                            code = "xc_fromjson_" + tn + "(xstd_json_parse(xstd_chan_recv(" + recv + ")))"
                            typ = tn
                            p = p + 4
                            if toks.kindAt(p) == 101 { p = p + 1 }   // )
                        }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "close" { code = "xstd_chan_close(" + recv + ")"  typ = "" }
                        p = al.pos
                    } }
                } else {
                if typ == "Thread" {
                    let al = genArgs(toks, p + 2, ctx)
                    if fld == "stop"    { code = "xstd_thread_stop("    + code + ")"  typ = "" }
                    if fld == "wait"    { code = "xstd_thread_wait("    + code + ")"  typ = "" }
                    if fld == "running" { code = "xstd_thread_running(" + code + ")"  typ = "Bool" }
                    p = al.pos
                } else {
                if typ.isListXType() {
                    let recv = code
                    let elem = typ.listElemCtype()
                    if fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_list_push(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""
                        p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "get" {
                        let al = genArgs(toks, p + 2, ctx)
                        code = "(*(" + elem + "*)xstd_list_at(" + recv + ", " + al.code + "))"
                        typ = typ.listElemXName()
                        p = al.pos
                    } else {
                    if fld == "set" or fld == "insert" {
                        let ie = genExpr(toks, p + 3, ctx)
                        let q = ie.pos
                        if toks.kindAt(q) == 106 { q = q + 1 }   // ,
                        let ve = genExpr(toks, q, ctx)
                        let op = "xstd_list_set"
                        if fld == "insert" { op = "xstd_list_insert" }
                        code = op + "(" + recv + ", " + ie.code + ", (" + elem + "[]){ " + ve.code + " })"
                        typ = ""
                        p = ve.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "len"      { code = "xstd_list_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty"  { code = "(xstd_list_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "removeAt" { code = "xstd_list_removeat(" + recv + ", " + al.code + ")"  typ = "" }
                        if fld == "swap"     { code = "xstd_list_swap(" + recv + ", " + al.code + ")"  typ = "" }
                        if fld == "clear"    { code = "xstd_list_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    } } }
                } else {
                if typ.isSetXType() {
                    let recv = code
                    let elem = typ.setElemCtype()
                    if fld == "add" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_set_add(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""
                        p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "contains" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_set_contains(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = "Bool"
                        p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "remove" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_set_remove(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""
                        p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "len"     { code = "xstd_set_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_set_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_set_clear(" + recv + ")"  typ = "" }
                        if fld == "items"   { code = "xstd_set_items(" + recv + ")"  typ = "List_" + typ.setElemSuffix() }
                        p = al.pos
                    } } }
                } else {
                if typ.isMapXType() {
                    let recv = code
                    let kc = typ.mapKeyCtype()
                    let vc = typ.mapValCtype()
                    if fld == "put" {
                        let ke = genExpr(toks, p + 3, ctx)
                        let q = ke.pos
                        if toks.kindAt(q) == 106 { q = q + 1 }   // ,
                        let ve = genExpr(toks, q, ctx)
                        code = "xstd_map_put(" + recv + ", (" + kc + "[]){ " + ke.code + " }, (" + vc + "[]){ " + ve.code + " })"
                        typ = ""
                        p = ve.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "get" {
                        let ke = genExpr(toks, p + 3, ctx)
                        code = "(*(" + vc + "*)xstd_map_get(" + recv + ", (" + kc + "[]){ " + ke.code + " }))"
                        typ = typ.mapValXName()
                        p = ke.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "getOr" {
                        let ke = genExpr(toks, p + 3, ctx)
                        let q = ke.pos
                        if toks.kindAt(q) == 106 { q = q + 1 }   // ,
                        let de = genExpr(toks, q, ctx)
                        code = "(*(" + vc + "*)xstd_map_getor(" + recv + ", (" + kc + "[]){ " + ke.code + " }, (" + vc + "[]){ " + de.code + " }))"
                        typ = typ.mapValXName()
                        p = de.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "has" {
                        let ke = genExpr(toks, p + 3, ctx)
                        code = "xstd_map_has(" + recv + ", (" + kc + "[]){ " + ke.code + " })"
                        typ = "Bool"
                        p = ke.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                    if fld == "remove" {
                        let ke = genExpr(toks, p + 3, ctx)
                        code = "xstd_map_remove(" + recv + ", (" + kc + "[]){ " + ke.code + " })"
                        typ = ""
                        p = ke.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "len"     { code = "xstd_map_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_map_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_map_clear(" + recv + ")"  typ = "" }
                        if fld == "keys"    { code = "xstd_map_keys(" + recv + ")"  typ = "List_" + typ.mapKeySuffix() }
                        if fld == "values"  { code = "xstd_map_values(" + recv + ")"  typ = "List_" + typ.mapValSuffix() }
                        p = al.pos
                    } } } } }
                } else {
                if typ.isStackXType() {
                    let recv = code
                    let elem = typ.stackElemCtype()
                    let elemX = typ.stackElemXName()
                    if fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_stack_push(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""  p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "pop"     { code = "({ " + elem + " _pv" + int_to_string(p) + "; xstd_stack_pop(" + recv + ", &_pv" + int_to_string(p) + "); _pv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "peek"    { code = "(*(" + elem + "*)xstd_stack_peek(" + recv + "))"  typ = elemX }
                        if fld == "len"     { code = "xstd_stack_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_stack_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_stack_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    }
                } else {
                if typ.isQueueXType() {
                    let recv = code
                    let elem = typ.queueElemCtype()
                    let elemX = typ.queueElemXName()
                    if fld == "enqueue" or fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_queue_enqueue(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""  p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "dequeue" { code = "({ " + elem + " _qv" + int_to_string(p) + "; xstd_queue_dequeue(" + recv + ", &_qv" + int_to_string(p) + "); _qv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "pop"     { code = "({ " + elem + " _qv" + int_to_string(p) + "; xstd_queue_dequeue(" + recv + ", &_qv" + int_to_string(p) + "); _qv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "peek"    { code = "(*(" + elem + "*)xstd_queue_peek(" + recv + "))"  typ = elemX }
                        if fld == "len"     { code = "xstd_queue_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_queue_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_queue_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    }
                } else {
                if typ.isSortedQueueXType() {
                    let recv = code
                    let elem = typ.sqElemCtype()
                    let elemX = typ.sqElemXName()
                    if fld == "push" {
                        let ae = genExpr(toks, p + 3, ctx)
                        code = "xstd_pqueue_push(" + recv + ", (" + elem + "[]){ " + ae.code + " })"
                        typ = ""  p = ae.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        if fld == "pop"     { code = "({ " + elem + " _hv" + int_to_string(p) + "; xstd_pqueue_pop(" + recv + ", &_hv" + int_to_string(p) + "); _hv" + int_to_string(p) + "; })"  typ = elemX }
                        if fld == "peek"    { code = "(*(" + elem + "*)xstd_pqueue_peek(" + recv + "))"  typ = elemX }
                        if fld == "len"     { code = "xstd_pqueue_len(" + recv + ")"  typ = "Integer" }
                        if fld == "isEmpty" { code = "(xstd_pqueue_len(" + recv + ") == 0)"  typ = "Bool" }
                        if fld == "clear"   { code = "xstd_pqueue_clear(" + recv + ")"  typ = "" }
                        p = al.pos
                    }
                } else {
                if typ == "HttpResponse" {
                    // res.send(dto): serialize via the DI-resolved WebTransport.
                    // res.sendStatus(code, msg) / res.sendText(code, body): plain text.
                    let recv = code
                    if fld == "send" {
                        let dtoE = genExpr(toks, p + 3, ctx)
                        code = "xstd_resp_set(" + recv + ", 200, xc_resolve_WebTransport().vtable->serialize(xc_resolve_WebTransport().self, " + jsonOfPayload(ctx.prog, dtoE.xtyp, dtoE.code) + "), xc_string_from_cstr(\"application/json\"))"
                        p = dtoE.pos
                        if toks.kindAt(p) == 101 { p = p + 1 }   // ')'
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        code = "xstd_resp_set(" + recv + ", " + al.code + ", xc_string_from_cstr(\"text/plain; charset=utf-8\"))"
                        p = al.pos
                    }
                    typ = ""
                } else {
                if typ == "HttpRequest" {
                    if fld == "parse" {
                        // req.parse(T): deserialize the body via WebTransport into a T.
                        let tn = toks.textAt(p + 3)
                        code = "xc_fromjson_" + tn + "(xc_resolve_WebTransport().vtable->deserialize(xc_resolve_WebTransport().self, xstd_req_body(" + code + ")))"
                        typ = tn
                        p = p + 4
                        if toks.kindAt(p) == 101 { p = p + 1 }   // ')'
                    } else {
                        let al = genArgs(toks, p + 2, ctx)
                        let recv = code
                        if fld == "query"  { code = "xstd_req_query("  + recv + ", " + al.code + ")" }
                        if fld == "header" { code = "xstd_req_header(" + recv + ", " + al.code + ")" }
                        if fld == "body"   { code = "xstd_req_body("   + recv + ")" }
                        if fld == "method" { code = "xstd_req_method(" + recv + ")" }
                        if fld == "path"   { code = "xstd_req_path("   + recv + ")" }
                        typ = "String"
                        p = al.pos
                    }
                } else {
                if typ == "PublisherService" and fld == "publish" {
                    // publish(topic, dto): wrap the typed DTO into an Event envelope.
                    let recv = code
                    let topicE = genExpr(toks, p + 3, ctx)
                    let q = topicE.pos
                    if toks.kindAt(q) == 106 { q = q + 1 }   // ','
                    let dtoE = genExpr(toks, q, ctx)
                    code = recv + ".vtable->publish(" + recv + ".self, xc_wrap_" + dtoE.xtyp
                         + "(" + topicE.code + ", " + dtoE.code + "))"
                    typ = ""
                    p = dtoE.pos
                    if toks.kindAt(p) == 101 { p = p + 1 }   // ')'
                } else {
                let al = genArgs(toks, p + 2, ctx)
                if typ.startsWith2("atom:") {
                    let an = string_slice(typ, 5, string_len(typ))
                    if fld == "undo" {
                        // atom.undo(): revert to the previous state (no-op if none)
                        code = "xc_atom_" + an + "_undo()"
                        typ = (ctx.prog).atomStateTypeName(an)
                    } else {
                    if fld == "canUndo" {
                        code = "(__atom_" + an + "_histlen > 0)"
                        typ = "Bool"
                    } else {
                        // atom.transition(args): push history, swap to the reducer result
                        let sep = ""
                        if string_len(al.code) > 0 { sep = ", " }
                        code = "(xc_atom_" + an + "_push(), __atom_" + an + " = xc_" + an + "__" + fld + "(__atom_" + an + sep + al.code + "))"
                        typ = (ctx.prog).atomStateTypeName(an)
                    } }
                } else {
                if typ.startsWith2("machinetype:") {
                    // Machine.start(...) -> xc_Machine__start(...)
                    let mmn = string_slice(typ, 12, string_len(typ))
                    code = "xc_" + mmn + "__" + fld + "(" + al.code + ")"
                    typ = mmn
                } else {
                if (ctx.prog).isMachineTypeC(typ) {
                    if fld == "can" {
                        // m.can(transition, args?) -> xc_M__can_<transition>(value, args?)
                        // first arg is the transition NAME (a bare identifier).
                        let tname = toks.textAt(p + 3)
                        let q = p + 4
                        if toks.kindAt(q) == 106 { q = q + 1 }   // skip ',' after name
                        let restargs = ""
                        let firstA = true
                        while toks.kindAt(q) != 101 and toks.kindAt(q) != 0 {
                            let a = genExpr(toks, q, ctx)
                            q = a.pos
                            if not firstA { restargs = restargs + ", " }
                            restargs = restargs + a.code
                            firstA = false
                            if toks.kindAt(q) == 106 { q = q + 1 }
                        }
                        let csep = ""
                        if string_len(restargs) > 0 { csep = ", " }
                        code = "xc_" + typ + "__can_" + tname + "(" + code + csep + restargs + ")"
                        typ = "Bool"
                    } else {
                        // machineValue.transition(args) -> xc_M__transition(value, args)
                        let msep = ""
                        if string_len(al.code) > 0 { msep = ", " }
                        code = "xc_" + typ + "__" + fld + "(" + code + msep + al.code + ")"
                        if fld == "isTerminal" { typ = "Bool" }
                    }
                } else {
                if typ.startsWith2("module:") and fld == "resolve" {
                    // Module.resolve(I) -> automatic interface resolver
                    code = "xc_resolve_" + al.firstRaw + "()"
                    typ = al.firstRaw
                } else {
                    if typ.startsWith2("ns:") {
                        let path = string_slice(typ, 3, string_len(typ)) + "." + fld
                        code = path.builtinForPath() + "(" + al.code + ")"
                        typ = ""
                    } else {
                        if isInterface(ctx.prog, typ) {
                            let sep = ""
                            if string_len(al.code) > 0 { sep = ", " }
                            let mret = ifaceMethodRet(ctx.prog, typ, fld)
                            code = code + ".vtable->" + fld + "(" + code + ".self" + sep + al.code + ")"
                            typ = mret
                        } else {
                            if (ctx.prog).isTypeNameC(typ) {
                                code = "xc_" + typ + "_" + fld + "(" + al.code + ")"
                                typ = ""
                            } else {
                                code = code + "." + fld + "(" + al.code + ")"
                                typ = ""
                            }
                        }
                    }
                }
                }
                }
                }
                p = al.pos
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
            } else {
                if typ == "HttpRequest" {
                    // bare request accessors: req.path / req.method / req.body
                    if fld == "path"   { code = "xstd_req_path("   + code + ")" }
                    if fld == "method" { code = "xstd_req_method(" + code + ")" }
                    if fld == "body"   { code = "xstd_req_body("   + code + ")" }
                    typ = "String"
                } else {
                if typ == "self" {
                    // self.<field> — a mutable state field or injected dep of the
                    // enclosing class; `self` is a struct pointer, so use `->`.
                    // (Assignment `self.x = e` reuses this via genExpr on the LHS.)
                    code = code + "->" + fld
                    typ = (ctx.prog).classFieldXType(ctx.selfClass, fld)
                } else {
                if typ.startsWith2("module:") and string_len((ctx.prog).moduleConstXType(string_slice(typ, 7, string_len(typ)), fld)) > 0 {
                    // Module.NAME — a module-scoped const, lowered to its getter.
                    let mnm = string_slice(typ, 7, string_len(typ))
                    code = "xc_" + mnm + "_" + fld + "()"
                    typ = (ctx.prog).moduleConstXType(mnm, fld)
                } else {
                if typ.startsWith2("atom:") {
                    // atom.current (or any field) -> the holder value
                    let an = string_slice(typ, 5, string_len(typ))
                    code = "__atom_" + an
                    typ = (ctx.prog).atomStateTypeName(an)
                } else {
                if (ctx.prog).isMachineTypeC(typ) and fld == "state" {
                    code = "xc_" + typ + "__state(" + code + ")"
                    typ = "String"
                } else {
                if typ.startsWith2("ns:") {
                    typ = "ns:" + string_slice(typ, 3, string_len(typ)) + "." + fld
                } else {
                    if fld == "data" and typ.startsWith2("arr_") {
                        // raw element pointer of an array fat pointer
                        code = code + ".data"
                        typ = "ptr:" + string_slice(typ, 4, string_len(typ)).xnameFromArrSuffix()
                    } else {
                        if typ.isPairXType() and (fld == "first" or fld == "second") {
                            // Pair<A,B>.first / .second — cast the stored value back to A/B.
                            let pex = typ.pairElem(0)
                            if fld == "second" { pex = typ.pairElem(1) }
                            code = "(*(" + pex.xnameToCtype() + "*)((" + code + ")." + fld + "))"
                            typ = pex
                        } else {
                        if typ == "String" and fld == "length" {
                            // string `.length` -> runtime length
                            code = "xstd_strlen(" + code + ")"
                            typ = "Integer"
                        } else {
                            let ft = (ctx.prog).fieldTypeNameC(typ, fld)
                            // Field access on a declared compound type whose field
                            // set is fixed: a name that is not a declared field is a
                            // typo. Report it in Xi terms instead of leaking a C
                            // `no member named`. (Test name presence, not ft — a
                            // valid field of sum-type resolves ft to "".)
                            if (ctx.prog).isCompoundTypeC(typ) and not (ctx.prog).hasFieldC(typ, fld) {
                                diag_error(tokenArrGet(toks, p + 1).line, "type '" + typ + "' has no field '" + fld + "'")
                            }
                            code = code + "." + fld
                            typ = ft
                        }
                        }
                    }
                }
                }
                }
                }
                }
                }
                p = p + 2
            }
            }
            }
        } else {
            if k == 100 {
                let al = genArgs(toks, p, ctx)
                let _fx = ctx.lookupVar(bname)
                if _fx.isFnXType() {
                    // Closure call: cast the stored fn pointer to the signature
                    // recovered from the value's Fn(...) xtype and invoke it.
                    let rc = _fx.fnRetX()
                    let pcs = _fx.fnParamsX()
                    let sig = rc + "(*)(void*"
                    if string_len(pcs) > 0 { sig = sig + ", " + pcs }
                    sig = sig + ")"
                    let cargs = "(" + bname + ").env"
                    if string_len(al.code) > 0 { cargs = cargs + ", " + al.code }
                    code = "((" + sig + ")(" + bname + ").fn)(" + cargs + ")"
                    typ = rc.ctypeToXName()
                } else {
                if bname == "ok" {
                    // ok(x) -> build the enclosing function's Result with .ok=true
                    code = "(" + ctx.retCtype + "){ .ok = true, .value = " + al.code + " }"
                    typ = ""
                } else {
                if bname == "err" {
                    code = "(" + ctx.retCtype + "){ .ok = false, .err = " + al.code + " }"
                    typ = ""
                } else {
                if bname == "isOk" {
                    code = "((" + al.code + ").ok)"
                    typ = "Bool"
                } else {
                if bname == "isErr" {
                    code = "(!(" + al.code + ").ok)"
                    typ = "Bool"
                } else {
                if string_len(ctx.selfClass) > 0 and (ctx.prog).isSelfMethodC(ctx.selfClass, bname) {
                    // Unqualified (or recursive) call to a sibling method.
                    let sargs = "self"
                    if string_len(al.code) > 0 { sargs = "self, " + al.code }
                    code = "xc_" + ctx.selfClass + "_" + bname + "_impl(" + sargs + ")"
                    typ = (ctx.prog).selfMethodRetXType(ctx.selfClass, bname)
                } else {
                if (ctx.prog).isFuncNameC(bname) {
                    if ctx.prog.isAsyncFuncC(bname) {
                        // async call: spawn a worker, yield a Future immediately
                        code = "xc_spawn_" + bname + "(" + al.code + ")"
                    } else {
                        code = "xc_" + bname + "(" + al.code + ")"
                    }
                    typ = (ctx.prog).funcRetXType(bname)
                } else {
                    if (ctx.prog).isExternNameC(bname) {
                        code = bname + "(" + al.code + ")"
                        typ = (ctx.prog).externRetXType(bname)
                    } else {
                        // Unresolved call. If it's a known std-library symbol, the
                        // module just isn't imported — report that in Xi terms
                        // (diag_error prints `<file>:<line>: error: …` and exits)
                        // instead of leaking a C error on the generated call.
                        let hint = bname.stdImportHint()
                        if string_len(hint) > 0 {
                            diag_error(tokenArrGet(toks, pos).line, bname + "(...) is defined in " + hint + " — add:  import \"" + hint + "\"")
                        }
                        code = bname + "(" + al.code + ")"
                        typ = ""
                    }
                }
                }
                }
                }
                }
                }
                }
                p = al.pos
            } else {
                if k == 104 {
                    let ie = genExpr(toks, p + 1, ctx)
                    let p2 = ie.pos
                    if toks.kindAt(p2) == 105 { p2 = p2 + 1 }
                    if typ.startsWith2("ptr:") {
                        // already a raw pointer (e.g. arr.data) — index directly
                        code = code + "[" + ie.code + "]"
                        typ = string_slice(typ, 4, string_len(typ))
                    } else {
                        if typ.startsWith2("arr_") {
                            code = code + ".data[" + ie.code + "]"
                            typ = string_slice(typ, 4, string_len(typ)).xnameFromArrSuffix()
                        } else {
                            if typ.endsWith2("[]") {
                                code = code + ".data[" + ie.code + "]"
                                typ = string_slice(typ, 0, string_len(typ) - 2)
                            } else {
                                code = code + ".data[" + ie.code + "]"
                                typ = ""
                            }
                        }
                    }
                    p = p2
                } else {
                    if k == 128 {
                        // ?? null-coalesce
                        let r = genPostfix(toks, p + 1, ctx)
                        code = "(" + code + ".has_value ? " + code + ".value : " + r.code + ")"
                        p = r.pos
                    } else {
                    if k == 209 and toks.kindAt(p + 1) == 1 and toks.textAt(p + 1) == "Json" {
                        // `<obj> as Json` — serialize a compound value (or a bare
                        // List<T>/T[]) into a Json tree (the mirror of `<json> as T`).
                        code = jsonOfPayload(ctx.prog, typ, code)
                        typ = "Json"
                        p = p + 2
                    } else {
                    if k == 209 and toks.kindAt(p + 1) == 1 and (ctx.prog).isTypeNameC(toks.textAt(p + 1)) {
                        // `<json> as T` — decode a Json value into a typed T (lenient
                        // coercion of string scalars). Reuses the derived JSON codec.
                        let tn = toks.textAt(p + 1)
                        code = "xc_fromjson_" + tn + "(" + code + ")"
                        typ = tn
                        p = p + 2
                    } else {
                    if k == 1 and toks.textAt(p) == "capture" and toks.kindAt(p + 1) == 1 and toks.kindAt(p + 2) == 108 {
                        // `<expr> capture name: Type` — bind the value to `name` (declared
                        // at the function top by the capture pre-scan) and yield it.
                        let nm = toks.textAt(p + 1)
                        code = "(" + nm + " = (" + code + "))"
                        p = p + 4                         // capture name : Type
                    } else {
                        // NOTE: a lone '?' (kind 127) is left unconsumed here so the
                        // statement layer can lower it as Result error-propagation.
                        cont = false
                    }
                    }
                    }
                    }
                }
            }
        }
    }
    return ExprRes { code: code, pos: p, xtyp: typ , owned: false }
}
