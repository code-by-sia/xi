// xc codegen — JSON codecs + event/web dispatch
// (part of the generator — spliced via the xc.xi manifest)

// xc codegen — codecs, event/web dispatch, entry, atoms, machines, genAll
// (part of the xc code generator — Program -> C99; spliced via codegen.xi)

// Return the last whitespace-separated word of a string (e.g. param name)
mapper lastWord(s: String) -> String {
    let n = string_len(s)
    let lastSp = 0 - 1
    let i = 0
    while i < n {
        if string_char_at(s, i) == 32 { lastSp = i }
        i = i + 1
    }
    return string_slice(s, lastSp + 1, n)
}

// Find a TypeSpec by X name (empty spec if absent).
mapper findTypeSpec(prog: Program, name: String) -> TypeSpec {
    let empty: String[] = []
    let none: Token[] = []
    let i = 0
    let n = typeSpecLen(prog.types)
    while i < n {
        let ts = typeSpecGet(prog.types, i)
        if ts.name == name { return ts }
        i = i + 1
    }
    return TypeSpec { name: "", isCompound: false, baseCtype: "", fields: empty, hasWhere: false, whereSrc: "", whereTokens: none, isSum: false, variants: [] }
}

// True if the app binds a non-default (non-LocalBus) PublisherService — i.e. an
// external transport, so emit should also serialize and publish on the wire.
predicate hasExternalPublisher(prog: Program) {
    let i = 0
    let n = moduleSpecLen(prog.modules)
    while i < n {
        let m = moduleSpecGet(prog.modules, i)
        let j = 0
        let bn = bindSpecLen(m.bindings)
        while j < bn {
            let b = bindSpecGet(m.bindings, j)
            if b.ifaceName == "PublisherService" and b.concreteName != "LocalBus" { return true }
            j = j + 1
        }
        i = i + 1
    }
    return false
}

// JSON encode/decode expressions for one field ctype ("" = unsupported -> skip).
// Element C type of an array ctype "xc_arr_<suffix>_t".
mapper arrElemCtype(fct: String) -> String {
    let suf = string_slice(fct, 7, string_len(fct) - 2)   // strip "xc_arr_" and "_t"
    if suf == "string"  { return "xc_string_t" }
    if suf == "number"  { return "xc_number_t" }
    if suf == "integer" { return "xc_integer_t" }
    if suf == "bool"    { return "xc_bool_t" }
    if suf == "char"    { return "xc_char_t" }
    return "xc_" + suf + "_t"
}

mapper jsonEncodeExpr(prog: Program, fct: String, expr: String) -> String {
    match fct {
        "xc_string_t"  -> "xstd_json_string(" + expr + ")"
        "xc_number_t"  -> "xstd_json_number(" + expr + ")"
        "xc_integer_t" -> "xstd_json_number((xc_number_t)(" + expr + "))"
        "xc_bool_t"    -> "xstd_json_bool(" + expr + ")"
        "xc_Json_t"    -> expr
        _ -> {
            let xn = fct.ctypeToXName()
            if prog.hasCodec(xn) { return "xc_tojson_" + xn + "(" + expr + ")" }
            return ""
        }
    }
}
mapper jsonDecodeExpr(prog: Program, fct: String, getexpr: String) -> String {
    match fct {
        "xc_string_t"  -> "xstd_json_as_string(" + getexpr + ")"
        "xc_number_t"  -> "xstd_json_as_number(" + getexpr + ")"
        "xc_integer_t" -> "(xc_integer_t)xstd_json_as_number(" + getexpr + ")"
        "xc_bool_t"    -> "xstd_json_as_bool(" + getexpr + ")"
        "xc_Json_t"    -> getexpr
        _ -> {
            let xn = fct.ctypeToXName()
            if prog.hasCodec(xn) { return "xc_fromjson_" + xn + "(" + getexpr + ")" }
            return ""
        }
    }
}

// Derived JSON codec for one event type (used only at the process boundary).

// JsonCodecs — the default Codecs: emits JSON (de)serialization + event/web
// dispatch. A clean leaf (no calls back into expression/statement gen), so it
// is an injected component. genOneCodec is a private helper method.
class JsonCodecs implements Codecs {
    deps {}
    mapper genOneCodec(prog: Program, t: String) -> String {
        let ts = findTypeSpec(prog, t)
        let to = "static xc_Json_t xc_tojson_" + t + "(xc_" + t + "_t v) {\n    xc_Json_t o = xstd_json_object();\n"
        let fr = "static xc_" + t + "_t xc_fromjson_" + t + "(xc_Json_t j) {\n    xc_" + t + "_t v; memset(&v, 0, sizeof(v));\n"
        let nf = stringArrLen(ts.fields)
        let i = 0
        while i < nf {
            let entry = stringArrGet(ts.fields, i)
            let colon = findChar(entry, 58)
            let fname = string_slice(entry, 0, colon)
            let fct = string_slice(entry, colon + 1, string_len(entry))
            let key = "xc_string_from_cstr(\"" + fname + "\")"
            if fct.startsWith2("xc_arr_") {
                // array field -> a JSON array, element by element
                let ec = arrElemCtype(fct)
                let sx = int_to_string(i)
                let encE = jsonEncodeExpr(prog, ec, "v." + fname + ".data[__i" + sx + "]")
                let decE = jsonDecodeExpr(prog, ec, "xstd_json_at(__a" + sx + ", __i" + sx + ")")
                if string_len(encE) > 0 {
                    to = to + "    { xc_Json_t __a" + sx + " = xstd_json_array();\n"
                       + "      for (xc_integer_t __i" + sx + " = 0; __i" + sx + " < (xc_integer_t)v." + fname + ".len; __i" + sx + "++)\n"
                       + "          xstd_json_push(__a" + sx + ", " + encE + ");\n"
                       + "      o = xstd_json_set(o, " + key + ", __a" + sx + "); }\n"
                }
                if string_len(decE) > 0 {
                    fr = fr + "    { xc_Json_t __a" + sx + " = xstd_json_get(j, " + key + ");\n"
                       + "      xc_integer_t __n" + sx + " = xstd_json_length(__a" + sx + ");\n"
                       + "      " + fct + " __r" + sx + "; __r" + sx + ".len = (xc_size_t)__n" + sx + "; __r" + sx + ".cap = (xc_size_t)__n" + sx + ";\n"
                       + "      __r" + sx + ".data = __n" + sx + " > 0 ? (" + ec + "*)malloc((xc_size_t)__n" + sx + " * sizeof(" + ec + ")) : (" + ec + "*)0;\n"
                       + "      for (xc_integer_t __i" + sx + " = 0; __i" + sx + " < __n" + sx + "; __i" + sx + "++)\n"
                       + "          __r" + sx + ".data[__i" + sx + "] = " + decE + ";\n"
                       + "      v." + fname + " = __r" + sx + "; }\n"
                }
            } else {
                let enc = jsonEncodeExpr(prog, fct, "v." + fname)
                if string_len(enc) > 0 { to = to + "    o = xstd_json_set(o, " + key + ", " + enc + ");\n" }
                let dec = jsonDecodeExpr(prog, fct, "xstd_json_get(j, " + key + ")")
                if string_len(dec) > 0 { fr = fr + "    v." + fname + " = " + dec + ";\n" }
            }
            i = i + 1
        }
        to = to + "    return o;\n}\n"
        fr = fr + "    return v;\n}\n"
        return to + fr
    }

    // toJson/fromJson for every event type. Emitted but invoked only by external
    // transports (in-process dispatch never serializes).
    mapper genEventCodecs(prog: Program) -> String {
        // Codecs are derived for every event type, and — when std/web is in use — for
        // every compound type as well (so res.send(dto) / req.parse(T) auto-serialize).
        let types: String[] = []
        let ei = 0
        let ne = stringArrLen(prog.eventTypes)
        while ei < ne {
            types = appendString(types, stringArrGet(prog.eventTypes, ei))
            ei = ei + 1
        }
        if prog.codecsEnabled() {
            let ti = 0
            let tn = typeSpecLen(prog.types)
            while ti < tn {
                let ts = typeSpecGet(prog.types, ti)
                if ts.isCompound and not strArrContains(types, ts.name) {
                    types = appendString(types, ts.name)
                }
                ti = ti + 1
            }
        }
        let nc = stringArrLen(types)
        if nc == 0 { return "" }
        let out = "/* === Derived JSON codecs (toJson/fromJson) === */\n"
        out = out + "extern xc_Json_t xstd_json_object(void);\n"
        out = out + "extern xc_Json_t xstd_json_set(xc_Json_t, xc_string_t, xc_Json_t);\n"
        out = out + "extern xc_Json_t xstd_json_string(xc_string_t);\n"
        out = out + "extern xc_Json_t xstd_json_number(xc_number_t);\n"
        out = out + "extern xc_Json_t xstd_json_bool(xc_bool_t);\n"
        out = out + "extern xc_Json_t xstd_json_get(xc_Json_t, xc_string_t);\n"
        out = out + "extern xc_string_t xstd_json_as_string(xc_Json_t);\n"
        out = out + "extern xc_number_t xstd_json_as_number(xc_Json_t);\n"
        out = out + "extern xc_bool_t xstd_json_as_bool(xc_Json_t);\n"
        out = out + "extern xc_Json_t xstd_json_array(void);\n"
        out = out + "extern xc_Json_t xstd_json_push(xc_Json_t, xc_Json_t);\n"
        out = out + "extern xc_integer_t xstd_json_length(xc_Json_t);\n"
        out = out + "extern xc_Json_t xstd_json_at(xc_Json_t, xc_integer_t);\n"
        out = out + "extern xc_string_t xstd_json_stringify(xc_Json_t);\n"
        out = out + "extern xc_Json_t xstd_json_parse(xc_string_t);\n"
        let i = 0
        while i < nc {
            let t = stringArrGet(types, i)
            out = out + "static xc_Json_t xc_tojson_" + t + "(xc_" + t + "_t);\n"
            out = out + "static xc_" + t + "_t xc_fromjson_" + t + "(xc_Json_t);\n"
            i = i + 1
        }
        i = 0
        while i < nc {
            out = out + genOneCodec(prog, stringArrGet(types, i))
            i = i + 1
        }
        return out + "\n"
    }

    // Forward declarations for the typed emitters and the inbound router, so call
    // sites (in producer bodies) resolve before the definitions.
    // Forward declarations for the per-type wrap helpers and the built-in event
    // facility, so producer/consumer bodies resolve before the definitions.
    mapper genEventFwd(prog: Program) -> String {
        let ne = stringArrLen(prog.eventTypes)
        if ne == 0 { return "" }
        let out = "/* === Event forward decls === */\n"
        let i = 0
        while i < ne {
            let t = stringArrGet(prog.eventTypes, i)
            out = out + "static xc_Event_t xc_wrap_" + t + "(xc_string_t, xc_" + t + "_t);\n"
            i = i + 1
        }
        out = out + "static void xc_event_dispatch(xc_Event_t);\n"
        out = out + "static xc_Json_t xc_event_encode(xc_Event_t);\n"
        out = out + "static xc_Event_t xc_event_decode(xc_string_t, xc_string_t, xc_Json_t);\n"
        if isInterface(prog, "ConsumerService") {
            out = out + "static void xc_events_run(void);\n"
        }
        out = out + "static xc_Thread_t xc_events_run_async(void);\n"
        return out + "\n"
    }

    // The typed event machinery: per-type envelope wrappers (heap-copy the DTO, no
    // serialization), the dispatcher that routes an envelope to the typed listeners,
    // and the encode/decode helpers + pump runner used by external transports.
    mapper genEventDispatch(prog: Program) -> String {
        let ne = stringArrLen(prog.eventTypes)
        if ne == 0 { return "" }
        let out = "/* === Event dispatch (typed envelopes) === */\n"
        // per-type wrap helpers: heap-copy the value into an envelope.
        let i = 0
        while i < ne {
            let t = stringArrGet(prog.eventTypes, i)
            out = out + "static xc_Event_t xc_wrap_" + t + "(xc_string_t topic, xc_" + t + "_t v) {\n"
            out = out + "    xc_" + t + "_t* p = (xc_" + t + "_t*)malloc(sizeof(xc_" + t + "_t));\n"
            out = out + "    if (!p) abort();\n    *p = v;\n"
            out = out + "    return xstd_event_make(topic, xc_string_from_cstr(\"" + t + "\"), (void*)p);\n}\n"
            i = i + 1
        }
        // dispatcher: typed-listener trampolines + a topic/type match table.
        let disp = "static void xc_event_dispatch(xc_Event_t __e) {\n"
        disp = disp + "    xc_string_t __t = xstd_event_topic(__e);\n"
        disp = disp + "    xc_string_t __ty = xstd_event_type(__e);\n"
        disp = disp + "    void* __pl = xstd_event_payload(__e);\n"
        disp = disp + "    (void)__t; (void)__ty; (void)__pl;\n"
        let ci = 0
        let cn = classSpecLen(prog.classes)
        while ci < cn {
            let cs = classSpecGet(prog.classes, ci)
            let mi = 0
            let mn = methodSpecLen(cs.methList)
            while mi < mn {
                let ms = methodSpecGet(cs.methList, mi)
                let pt = ms.params.firstParamXType()
                if ms.kind == "listener" and string_len(ms.topic) > 0 and prog.isEventTypeC(pt) {
                    let tr = "xc_evtT_" + cs.name + "_" + ms.name
                    out = out + "static void " + tr + "(xc_" + pt + "_t e) {\n"
                    out = out + "    xc_" + cs.name + "_" + ms.name + "_impl((void*)xc_new_" + cs.name + "(), e);\n}\n"
                    disp = disp + "    if (xc_string_eq(__t, xc_string_from_cstr(\"" + ms.topic + "\")) && xc_string_eq(__ty, xc_string_from_cstr(\"" + pt + "\"))) " + tr + "(*(xc_" + pt + "_t*)__pl);\n"
                }
                mi = mi + 1
            }
            ci = ci + 1
        }
        disp = disp + "}\n"
        out = out + disp
        // encode: payload -> Json (by type name), for external transports.
        out = out + "static xc_Json_t xc_event_encode(xc_Event_t __e) {\n"
        out = out + "    xc_string_t __ty = xstd_event_type(__e);\n    void* __pl = xstd_event_payload(__e);\n"
        let ei = 0
        while ei < ne {
            let t = stringArrGet(prog.eventTypes, ei)
            out = out + "    if (xc_string_eq(__ty, xc_string_from_cstr(\"" + t + "\"))) return xc_tojson_" + t + "(*(xc_" + t + "_t*)__pl);\n"
            ei = ei + 1
        }
        out = out + "    return (xc_Json_t)0;\n}\n"
        // decode: (topic, type, Json) -> envelope, for external transports.
        out = out + "static xc_Event_t xc_event_decode(xc_string_t topic, xc_string_t type, xc_Json_t payload) {\n"
        let di = 0
        while di < ne {
            let t = stringArrGet(prog.eventTypes, di)
            out = out + "    if (xc_string_eq(type, xc_string_from_cstr(\"" + t + "\"))) return xc_wrap_" + t + "(topic, xc_fromjson_" + t + "(payload));\n"
            di = di + 1
        }
        out = out + "    return xstd_event_make(topic, type, (void*)0);\n}\n"
        // the pump: resolve the bound ConsumerService and run it.
        if isInterface(prog, "ConsumerService") {
            out = out + "static void xc_events_run(void) {\n"
            out = out + "    xc_ConsumerService_t __c = xc_resolve_ConsumerService();\n"
            out = out + "    __c.vtable->run(__c.self);\n}\n"
        }
        // async pump: a worker thread that blocks on the queue and dispatches each
        // event to its typed listeners, until Events.stop() closes the queue.
        out = out + "static void* xc_events_pump(void* __a) {\n"
        out = out + "    (void)__a;\n"
        out = out + "    for (;;) {\n"
        out = out + "        xc_Event_t __e = xstd_eventq_pop_blocking();\n"
        out = out + "        if (!__e) break;\n"
        out = out + "        xc_event_dispatch(__e);\n"
        out = out + "    }\n"
        out = out + "    return (void*)0;\n}\n"
        out = out + "static xc_Thread_t xc_events_run_async(void) {\n"
        out = out + "    return xstd_thread_spawn(xc_events_pump, (void*)0);\n}\n"
        return out + "\n"
    }

    // std/web (handler model): the runtime hands each request a fresh mutable
    // response. Every class implementing WebRequestHandler is a controller and is
    // auto-registered (DI-wired) — no explicit bind. Controllers are tried in
    // declaration order; the first whose handle sets the response wins. Routing is
    // the `where`-overloaded handle methods inside each controller.
    mapper genWebDispatch(prog: Program) -> String {
        if not prog.webEnabled() { return "" }
        let out = "/* === Web (WebRequestHandler controllers) === */\n"
        out = out + "static void xc_web_handle(xc_HttpRequest_t __req, xc_HttpResponse_t __res) {\n"
        let impls = implementorsOf(prog, "WebRequestHandler")
        let n = stringArrLen(impls)
        let i = 0
        while i < n {
            let c = stringArrGet(impls, i)
            out = out + "    { xc_WebRequestHandler_t __h = xc_" + c + "_as_WebRequestHandler(xc_new_" + c + "());\n"
            out = out + "      if (xstd_starts_with(xstd_req_path(__req), __h.vtable->getBaseUrl(__h.self))) {\n"
            out = out + "        __h.vtable->handle(__h.self, __req, __res);\n"
            out = out + "        if (xstd_resp_status(__res) != 0) return; } }\n"
            i = i + 1
        }
        out = out + "}\n"
        out = out + "static void xc_web_init(void) { xstd_web_set_handler(xc_web_handle); }\n\n"
        return out
    }

}
