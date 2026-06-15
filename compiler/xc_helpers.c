/*
 * xc_helpers.c — typed array helpers for the X self-hosting compiler
 *
 * Appended after the generated C so it can see all struct definitions.
 * Implements every extern "C" function declared in compiler/*.x.
 *
 * Pattern:
 *   DEFINE_TYPED_ARR(ElemType, ArrType, BaseName)
 *   generates:
 *     BaseName(arr, elem) -> ArrType   (the push / append function)
 *     BaseName_len(arr) -> integer     (internal len helper)
 *     BaseName_get(arr, i) -> Elem     (internal get helper)
 *   The extern-declared xyzLen / xyzGet aliases call these.
 */

/* ─── Generic typed-array macro ─────────────────────────────────────────── */

/*
 * X arrays have VALUE semantics: a fat pointer { data, len, cap } is copied
 * by value, so many independent copies may share one `data` buffer.  Growing
 * in place (realloc) would free a buffer still referenced by other copies
 * (use-after-free).
 *
 * Append uses amortised capacity doubling so that accumulating N elements costs
 * O(N) memory and time, not O(N^2).  Two cases:
 *   - len < cap : the buffer has spare room we allocated for this purpose, so
 *     write in place and bump len.  Array *literals* always emit cap == len
 *     (no spare), so they fall to the grow branch and are never mutated — the
 *     in-place path only ever fires on an accumulator we ourselves grew.
 *   - len == cap: allocate a fresh, larger buffer, copy, and return a new fat
 *     pointer.  The old buffer is left intact (no free), preserving the value
 *     semantics of any other copies that still reference it.
 */
#define DEFINE_TYPED_ARR(ElemType, ArrType, BaseName)                         \
                                                                              \
ArrType BaseName(ArrType arr, ElemType elem) {                                \
    if (arr.len < arr.cap) {                                                  \
        arr.data[arr.len] = elem;                                             \
        arr.len += 1;                                                         \
        return arr;                                                           \
    }                                                                         \
    xc_size_t need = arr.len + 1;                                             \
    xc_size_t ncap = arr.cap ? arr.cap * 2 : 4;                               \
    if (ncap < need) ncap = need;                                             \
    ElemType* nd = (ElemType*)malloc(ncap * sizeof(ElemType));                \
    if (!nd) { fputs("xc: out of memory\n", stderr); abort(); }              \
    if (arr.len) memcpy(nd, arr.data, arr.len * sizeof(ElemType));            \
    nd[arr.len] = elem;                                                       \
    ArrType out; out.data = nd; out.len = need; out.cap = ncap;               \
    return out;                                                               \
}                                                                             \
                                                                              \
static xc_integer_t BaseName##_len(ArrType arr) {                             \
    return (xc_integer_t)arr.len;                                             \
}                                                                             \
                                                                              \
static ElemType BaseName##_get(ArrType arr, xc_integer_t i) {                 \
    if (i < 0 || (xc_size_t)i >= arr.len) {                                   \
        fprintf(stderr, "xc: index %lld out of bounds (len %zu)\n",           \
                (long long)i, arr.len);                                        \
        abort();                                                               \
    }                                                                          \
    return arr.data[(xc_size_t)i];                                            \
}

/* ─── Instantiate for every typed array used in xc.x ───────────────────── */

DEFINE_TYPED_ARR(xc_FieldSpec_t,   xc_arr_FieldSpec_t,   appendFieldSpec)
DEFINE_TYPED_ARR(xc_MethodSpec_t,  xc_arr_MethodSpec_t,  appendMethodSpec)
DEFINE_TYPED_ARR(xc_TypeSpec_t,    xc_arr_TypeSpec_t,    appendTypeSpec)
DEFINE_TYPED_ARR(xc_IfaceSpec_t,   xc_arr_IfaceSpec_t,   appendIfaceSpec)
DEFINE_TYPED_ARR(xc_DepSpec_t,     xc_arr_DepSpec_t,     appendDepSpec)
DEFINE_TYPED_ARR(xc_ClassSpec_t,   xc_arr_ClassSpec_t,   appendClassSpec)
DEFINE_TYPED_ARR(xc_BindSpec_t,    xc_arr_BindSpec_t,    appendBindSpec)
DEFINE_TYPED_ARR(xc_ModuleSpec_t,  xc_arr_ModuleSpec_t,  appendModuleSpec)
DEFINE_TYPED_ARR(xc_FuncSpec_t,    xc_arr_FuncSpec_t,    appendFuncSpec)
DEFINE_TYPED_ARR(xc_AtomSpec_t,    xc_arr_AtomSpec_t,    appendAtomSpec)
DEFINE_TYPED_ARR(xc_MachineSpec_t, xc_arr_MachineSpec_t, appendMachineSpec)
DEFINE_TYPED_ARR(xc_MachineTransition_t, xc_arr_MachineTransition_t, appendMachineTransition)
DEFINE_TYPED_ARR(xc_DecisionRow_t,   xc_arr_DecisionRow_t,   appendDecisionRow)
DEFINE_TYPED_ARR(xc_DecisionTable_t, xc_arr_DecisionTable_t, appendDecisionTable)

/* ─── Token array ────────────────────────────────────────────────────────── */

xc_arr_Token_t appendTokenC(xc_arr_Token_t arr, xc_Token_t tok) {
    if (arr.len < arr.cap) { arr.data[arr.len] = tok; arr.len += 1; return arr; }
    xc_size_t need = arr.len + 1;
    xc_size_t ncap = arr.cap ? arr.cap * 2 : 4;
    if (ncap < need) ncap = need;
    xc_Token_t* nd = (xc_Token_t*)malloc(ncap * sizeof(xc_Token_t));
    if (!nd) abort();
    if (arr.len) memcpy(nd, arr.data, arr.len * sizeof(xc_Token_t));
    nd[arr.len] = tok;
    xc_arr_Token_t out; out.data = nd; out.len = need; out.cap = ncap;
    return out;
}
xc_integer_t tokenArrLen(xc_arr_Token_t arr) { return (xc_integer_t)arr.len; }
xc_Token_t tokenArrGet(xc_arr_Token_t arr, xc_integer_t i) {
    if (i < 0 || (xc_size_t)i >= arr.len)
        return (xc_Token_t){ .kind = 0LL, .text = {NULL,0}, .line = 0LL };
    return arr.data[(xc_size_t)i];
}

/* ─── String array ───────────────────────────────────────────────────────── */

xc_arr_string_t appendString(xc_arr_string_t arr, xc_string_t s) {
    if (arr.len < arr.cap) { arr.data[arr.len] = s; arr.len += 1; return arr; }
    xc_size_t need = arr.len + 1;
    xc_size_t ncap = arr.cap ? arr.cap * 2 : 4;
    if (ncap < need) ncap = need;
    xc_string_t* nd = (xc_string_t*)malloc(ncap * sizeof(xc_string_t));
    if (!nd) abort();
    if (arr.len) memcpy(nd, arr.data, arr.len * sizeof(xc_string_t));
    nd[arr.len] = s;
    xc_arr_string_t out; out.data = nd; out.len = need; out.cap = ncap;
    return out;
}
xc_integer_t stringArrLen(xc_arr_string_t arr) { return (xc_integer_t)arr.len; }
xc_string_t stringArrGet(xc_arr_string_t arr, xc_integer_t i) {
    if (i < 0 || (xc_size_t)i >= arr.len) {
        fprintf(stderr, "stringArrGet: index %lld out of bounds (%zu)\n",
                (long long)i, arr.len);
        abort();
    }
    return arr.data[(xc_size_t)i];
}

/* ─── Len / Get aliases (match the extern "C" declarations in xc.x) ──────── */

xc_integer_t methodSpecLen(xc_arr_MethodSpec_t a) { return appendMethodSpec_len(a); }
xc_MethodSpec_t methodSpecGet(xc_arr_MethodSpec_t a, xc_integer_t i) { return appendMethodSpec_get(a, i); }

xc_integer_t depSpecLen(xc_arr_DepSpec_t a)    { return appendDepSpec_len(a); }
xc_DepSpec_t depSpecGet(xc_arr_DepSpec_t a, xc_integer_t i) { return appendDepSpec_get(a, i); }

xc_integer_t bindSpecLen(xc_arr_BindSpec_t a)  { return appendBindSpec_len(a); }
xc_BindSpec_t bindSpecGet(xc_arr_BindSpec_t a, xc_integer_t i) { return appendBindSpec_get(a, i); }

xc_integer_t typeSpecLen(xc_arr_TypeSpec_t a)  { return appendTypeSpec_len(a); }
xc_TypeSpec_t typeSpecGet(xc_arr_TypeSpec_t a, xc_integer_t i) { return appendTypeSpec_get(a, i); }

xc_integer_t ifaceSpecLen(xc_arr_IfaceSpec_t a){ return appendIfaceSpec_len(a); }
xc_IfaceSpec_t ifaceSpecGet(xc_arr_IfaceSpec_t a, xc_integer_t i) { return appendIfaceSpec_get(a, i); }

xc_integer_t classSpecLen(xc_arr_ClassSpec_t a){ return appendClassSpec_len(a); }
xc_ClassSpec_t classSpecGet(xc_arr_ClassSpec_t a, xc_integer_t i) { return appendClassSpec_get(a, i); }

xc_integer_t moduleSpecLen(xc_arr_ModuleSpec_t a) { return appendModuleSpec_len(a); }
xc_ModuleSpec_t moduleSpecGet(xc_arr_ModuleSpec_t a, xc_integer_t i) { return appendModuleSpec_get(a, i); }

xc_integer_t funcSpecLen(xc_arr_FuncSpec_t a)  { return appendFuncSpec_len(a); }
xc_FuncSpec_t funcSpecGet(xc_arr_FuncSpec_t a, xc_integer_t i) { return appendFuncSpec_get(a, i); }

xc_integer_t atomSpecLen(xc_arr_AtomSpec_t a)  { return appendAtomSpec_len(a); }
xc_AtomSpec_t atomSpecGet(xc_arr_AtomSpec_t a, xc_integer_t i) { return appendAtomSpec_get(a, i); }

xc_integer_t machineSpecLen(xc_arr_MachineSpec_t a)  { return appendMachineSpec_len(a); }
xc_MachineSpec_t machineSpecGet(xc_arr_MachineSpec_t a, xc_integer_t i) { return appendMachineSpec_get(a, i); }

xc_integer_t machineTransLen(xc_arr_MachineTransition_t a) { return appendMachineTransition_len(a); }
xc_MachineTransition_t machineTransGet(xc_arr_MachineTransition_t a, xc_integer_t i) { return appendMachineTransition_get(a, i); }

xc_integer_t decisionRowLen(xc_arr_DecisionRow_t a) { return appendDecisionRow_len(a); }
xc_DecisionRow_t decisionRowGet(xc_arr_DecisionRow_t a, xc_integer_t i) { return appendDecisionRow_get(a, i); }
xc_integer_t decisionTableLen(xc_arr_DecisionTable_t a) { return appendDecisionTable_len(a); }
xc_DecisionTable_t decisionTableGet(xc_arr_DecisionTable_t a, xc_integer_t i) { return appendDecisionTable_get(a, i); }

/* ─── String utility ─────────────────────────────────────────────────────── */

xc_integer_t findChar(xc_string_t s, xc_integer_t c) {
    for (xc_size_t i = 0; i < s.len; i++)
        if ((xc_integer_t)(unsigned char)s.data[i] == c) return (xc_integer_t)i;
    return (xc_integer_t)s.len;
}

/* ─── Invoke the C compiler to produce a native executable ──────────────────
 * Compiles the generated C (cpath) together with the X runtime into a native
 * binary (binpath).  The runtime directory is taken from the XC_RUNTIME
 * environment variable, defaulting to "xc/runtime" (relative to cwd).        */
#ifndef XC_RUNTIME_DEFAULT
#define XC_RUNTIME_DEFAULT "runtime"
#endif

/* Append the contents of `src` onto the end of file `dst`. */
static int append_file(const char* dst, const char* src) {
    FILE* in = fopen(src, "rb");
    if (!in) return 1;
    FILE* out = fopen(dst, "ab");
    if (!out) { fclose(in); return 1; }
    char buf[8192];
    size_t r;
    fputs("\n/* === appended helpers === */\n", out);
    while ((r = fread(buf, 1, sizeof(buf), in)) > 0) fwrite(buf, 1, r, out);
    fclose(in); fclose(out);
    return 0;
}

/* Scan the generated C for a `/​* XC-BUILD-FLAGS: ... *​/` marker (emitted from
   `extern "C"` build directives) and expand it into extra cc flags. Tokens:
     pkg:NAME  -> the output of `pkg-config --cflags --libs NAME`
     <other>   -> appended literally (e.g. -lsqlite3, -I/x, -L/y). */
static void xc_build_flags(const char* cpath, char* out, size_t outsz) {
    out[0] = '\0';
    FILE* f = fopen(cpath, "rb");
    if (!f) return;
    char line[4096];
    char content[2048]; content[0] = '\0';
    int scanned = 0;
    /* The marker is emitted as a top-level comment near the file head. Match
       only when the (whitespace-trimmed) line *starts* with it, so the same
       text appearing inside a string literal deep in the generated C — which
       happens when the compiler compiles its own codegen.xi — is ignored. */
    while (fgets(line, sizeof(line), f) && scanned < 60) {
        scanned++;
        const char* p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (strncmp(p, "/* XC-BUILD-FLAGS:", 18) == 0) {
            const char* m = p + 18;
            char* end = strstr(m, "*/");
            char tmp[2048];
            snprintf(tmp, sizeof(tmp), "%s", m);
            if (end) { size_t off = (size_t)(end - m); if (off < sizeof(tmp)) tmp[off] = '\0'; }
            snprintf(content, sizeof(content), "%s", tmp);
            break;
        }
    }
    fclose(f);
    if (!content[0]) return;
    size_t used = 0;
    char* save = NULL;
    char* tok = strtok_r(content, " \t\r\n", &save);
    while (tok && used + 1 < outsz) {
        if (strncmp(tok, "pkg:", 4) == 0) {
            char cmd[512];
            snprintf(cmd, sizeof(cmd), "pkg-config --cflags --libs %s 2>/dev/null", tok + 4);
            FILE* pf = popen(cmd, "r");
            if (pf) {
                char pbuf[1024];
                if (fgets(pbuf, sizeof(pbuf), pf)) {
                    pbuf[strcspn(pbuf, "\n")] = '\0';
                    int n = snprintf(out + used, outsz - used, " %s", pbuf);
                    if (n > 0) used += (size_t)n;
                }
                pclose(pf);
            }
        } else {
            int n = snprintf(out + used, outsz - used, " %s", tok);
            if (n > 0) used += (size_t)n;
        }
        tok = strtok_r(NULL, " \t\r\n", &save);
    }
}

/* Set an environment variable in the current process. The driver uses this to
   pass the selected `--target` through to compile_c (read via getenv below). */
xc_integer_t set_env(xc_string_t name, xc_string_t value) {
    char* nm = xc_string_to_cstr(name);
    char* vl = xc_string_to_cstr(value);
    int rc = setenv(nm, vl, 1);
    free(nm); free(vl);
    return (xc_integer_t)(rc == 0 ? 0 : 1);
}

xc_integer_t compile_c(xc_string_t cpath, xc_string_t binpath) {
    char* cp = xc_string_to_cstr(cpath);
    char* bp = xc_string_to_cstr(binpath);
    const char* dir = getenv("XC_RUNTIME");
    if (!dir || !dir[0]) dir = XC_RUNTIME_DEFAULT;

    /* If XC_HELPERS names a C file, append it onto the generated C so its
       definitions (which reference the generated structs) share the TU. */
    const char* helpers = getenv("XC_HELPERS");
    if (helpers && helpers[0]) append_file(cp, helpers);

    /* User FFI flags from `extern "C"` directives (link libs, -I/-L, pkg-config). */
    char extra[4096]; extra[0] = '\0';
    xc_build_flags(cp, extra, sizeof(extra));

    /* Optional TLS (std/web HTTPS): opt-in via XC_TLS so default builds stay
       dependency-light. When set, enable XC_HAVE_TLS and link OpenSSL — flags
       from pkg-config when available, else a portable fallback (incl. Homebrew). */
    char tls[2048]; tls[0] = '\0';
    const char* want_tls   = getenv("XC_TLS");
    const char* want_http2 = getenv("XC_HTTP2");   /* implies TLS */
    if ((want_tls && want_tls[0]) || (want_http2 && want_http2[0])) {
        char pkg[768] = "";
        if (system("pkg-config --exists openssl 2>/dev/null") == 0) {
            FILE* pf = popen("pkg-config --cflags --libs openssl 2>/dev/null", "r");
            if (pf) { if (fgets(pkg, sizeof(pkg), pf)) { pkg[strcspn(pkg, "\n")] = '\0'; } pclose(pf); }
        }
        if (pkg[0]) {
            snprintf(tls, sizeof(tls), "-DXC_HAVE_TLS %s", pkg);
        } else {
            /* Fallback: common Homebrew prefixes (keg-only) + plain link flags. */
            snprintf(tls, sizeof(tls),
                     "-DXC_HAVE_TLS "
                     "-I/opt/homebrew/opt/openssl@3/include -L/opt/homebrew/opt/openssl@3/lib "
                     "-I/usr/local/opt/openssl@3/include -L/usr/local/opt/openssl@3/lib "
                     "-lssl -lcrypto");
        }
        if (want_http2 && want_http2[0]) {
            char h2[768] = "";
            if (system("pkg-config --exists libnghttp2 2>/dev/null") == 0) {
                FILE* pf = popen("pkg-config --cflags --libs libnghttp2 2>/dev/null", "r");
                if (pf) { if (fgets(h2, sizeof(h2), pf)) { h2[strcspn(h2, "\n")] = '\0'; } pclose(pf); }
            }
            size_t tl = strlen(tls);
            if (h2[0]) snprintf(tls + tl, sizeof(tls) - tl, " -DXC_HAVE_HTTP2 %s", h2);
            else       snprintf(tls + tl, sizeof(tls) - tl,
                                " -DXC_HAVE_HTTP2 "
                                "-I/opt/homebrew/opt/nghttp2/include -L/opt/homebrew/opt/nghttp2/lib "
                                "-lnghttp2");
        }
    }

    /* ── WebAssembly target (XC_TARGET=wasm): compile the same generated C +
       runtime through Emscripten into <binpath>.{html,js,wasm}. Single-threaded,
       and without the native FFI/TLS link flags — host libraries (OpenSSL,
       -l<lib> from pkg-config, etc.) aren't available in the browser sandbox. */
    const char* target = getenv("XC_TARGET");
    if (target && strcmp(target, "wasm") == 0) {
        if (system("command -v emcc >/dev/null 2>&1") != 0) {
            fprintf(stderr,
                "xc: --target wasm needs Emscripten (emcc) on PATH.\n"
                "    install it with:  brew install emscripten\n"
                "    or see https://emscripten.org/docs/getting_started/downloads.html\n");
            free(cp); free(bp); return 1;
        }
        size_t wneed = strlen(cp) + strlen(bp) + 3 * strlen(dir) + 512;
        char* wcmd = (char*)malloc(wneed);
        if (!wcmd) { free(cp); free(bp); return 1; }
        snprintf(wcmd, wneed,
                 "emcc -std=c99 -O2 -w -Wno-implicit-int -Wno-implicit-function-declaration "
                 "-Wno-int-conversion -Wno-incompatible-pointer-types "
                 "-I%s %s %s/runtime.c -o %s.html -lm "
                 "-sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1 -sASYNCIFY",
                 dir, cp, dir, bp);
        int wrc = system(wcmd);
        free(wcmd); free(cp); free(bp);
        if (wrc == -1) return 1;
        return (xc_integer_t)(wrc == 0 ? 0 : 1);
    }

    /* cc -std=c99 -O2 -I<dir> <cpath> <dir>/runtime.c -o <binpath> -lm -lpthread [tls] */
    size_t need = strlen(cp) + strlen(bp) + 3 * strlen(dir) + strlen(tls) + strlen(extra) + 256;
    char* cmd = (char*)malloc(need);
    if (!cmd) { free(cp); free(bp); return 1; }
    /* -w plus explicit -Wno-* because GCC 14 (Ubuntu 24.04) promotes these to
       hard errors that -w no longer silences; macOS clang only warns. */
    snprintf(cmd, need,
             "cc -std=c99 -O2 -w -Wno-implicit-int -Wno-implicit-function-declaration "
             "-Wno-int-conversion -Wno-incompatible-pointer-types "
             "-I%s %s %s/runtime.c -o %s -lm -lpthread %s%s",
             dir, cp, dir, bp, tls, extra);

    int rc = system(cmd);
    free(cmd); free(cp); free(bp);
    if (rc == -1) return 1;
    return (xc_integer_t)(rc == 0 ? 0 : 1);
}
