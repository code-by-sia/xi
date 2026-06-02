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
 * (use-after-free).  So append is functional: allocate a fresh buffer of
 * len+1, copy, and return a new fat pointer.  The old buffer is left intact.
 */
#define DEFINE_TYPED_ARR(ElemType, ArrType, BaseName)                         \
                                                                              \
ArrType BaseName(ArrType arr, ElemType elem) {                                \
    xc_size_t nl = arr.len + 1;                                               \
    ElemType* nd = (ElemType*)malloc(nl * sizeof(ElemType));                  \
    if (!nd) { fputs("xc: out of memory\n", stderr); abort(); }              \
    if (arr.len) memcpy(nd, arr.data, arr.len * sizeof(ElemType));            \
    nd[arr.len] = elem;                                                       \
    ArrType out; out.data = nd; out.len = nl; out.cap = nl;                   \
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

/* ─── Token array ────────────────────────────────────────────────────────── */

xc_arr_Token_t appendTokenC(xc_arr_Token_t arr, xc_Token_t tok) {
    xc_size_t nl = arr.len + 1;
    xc_Token_t* nd = (xc_Token_t*)malloc(nl * sizeof(xc_Token_t));
    if (!nd) abort();
    if (arr.len) memcpy(nd, arr.data, arr.len * sizeof(xc_Token_t));
    nd[arr.len] = tok;
    xc_arr_Token_t out; out.data = nd; out.len = nl; out.cap = nl;
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
    xc_size_t nl = arr.len + 1;
    xc_string_t* nd = (xc_string_t*)malloc(nl * sizeof(xc_string_t));
    if (!nd) abort();
    if (arr.len) memcpy(nd, arr.data, arr.len * sizeof(xc_string_t));
    nd[arr.len] = s;
    xc_arr_string_t out; out.data = nd; out.len = nl; out.cap = nl;
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

xc_integer_t compile_c(xc_string_t cpath, xc_string_t binpath) {
    char* cp = xc_string_to_cstr(cpath);
    char* bp = xc_string_to_cstr(binpath);
    const char* dir = getenv("XC_RUNTIME");
    if (!dir || !dir[0]) dir = XC_RUNTIME_DEFAULT;

    /* If XC_HELPERS names a C file, append it onto the generated C so its
       definitions (which reference the generated structs) share the TU. */
    const char* helpers = getenv("XC_HELPERS");
    if (helpers && helpers[0]) append_file(cp, helpers);

    /* cc -std=c99 -O2 -I<dir> <cpath> <dir>/runtime.c -o <binpath> -lm */
    size_t need = strlen(cp) + strlen(bp) + 3 * strlen(dir) + 128;
    char* cmd = (char*)malloc(need);
    if (!cmd) { free(cp); free(bp); return 1; }
    snprintf(cmd, need,
             "cc -std=c99 -O2 -w -I%s %s %s/runtime.c -o %s -lm",
             dir, cp, dir, bp);

    int rc = system(cmd);
    free(cmd); free(cp); free(bp);
    if (rc == -1) return 1;
    return (xc_integer_t)(rc == 0 ? 0 : 1);
}
