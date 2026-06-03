/*
 * runtime.c — X language runtime support implementation
 *
 * Contains functions that cannot be inlined in the header.
 */
#include "runtime.h"
#include <ctype.h>
#include <errno.h>

/* ─── Simple regex matching ──────────────────────────────────────────────── */

/*
 * Minimal regex engine supporting the constructs used in X refined types:
 *   .   any character
 *   *   zero or more of previous
 *   +   one or more of previous
 *   ?   zero or one of previous
 *   ^   start anchor (beginning of string)
 *   $   end anchor (end of string)
 *   [^...] negated character class
 *   \s  whitespace   \S  non-whitespace
 *   [...]  character class
 * All other characters are literal.
 *
 * This is not a full POSIX regex but covers the examples in the spec.
 */

static int regex_match_here(const char* re, const char* text);

static int regex_match_star(int c, const char* re, const char* text) {
    do {
        if (regex_match_here(re, text)) return 1;
    } while (*text != '\0' && (*text++ == c || c == '.'));
    return 0;
}

static int regex_match_plus(int c, const char* re, const char* text) {
    while (*text != '\0' && (*text == c || c == '.')) {
        text++;
        if (regex_match_here(re, text)) return 1;
    }
    return 0;
}

static int regex_char_in_class(const char* cls, char c, int *adv) {
    /* cls points after '['; returns 1 if c is in class, sets *adv to length consumed */
    int negate = 0;
    const char* p = cls;
    if (*p == '^') { negate = 1; p++; }
    int matched = 0;
    while (*p && *p != ']') {
        if (*(p+1) == '-' && *(p+2) && *(p+2) != ']') {
            if (c >= *p && c <= *(p+2)) matched = 1;
            p += 3;
        } else if (*p == '\\' && *(p+1)) {
            p++;
            switch (*p) {
                case 's': if (isspace(c)) matched = 1; break;
                case 'S': if (!isspace(c)) matched = 1; break;
                case 'd': if (isdigit(c)) matched = 1; break;
                case 'w': if (isalnum(c) || c == '_') matched = 1; break;
            }
            p++;
        } else {
            if (*p == c) matched = 1;
            p++;
        }
    }
    if (*p == ']') p++;
    *adv = (int)(p - cls);
    return negate ? !matched : matched;
}

static int regex_match_here(const char* re, const char* text) {
    if (re[0] == '\0') return 1;
    if (re[0] == '$' && re[1] == '\0') return *text == '\0';

    if (re[0] == '\\' && re[1] != '\0') {
        int matches = 0;
        switch (re[1]) {
            case 's': matches = isspace((unsigned char)*text); break;
            case 'S': matches = *text && !isspace((unsigned char)*text); break;
            case 'd': matches = isdigit((unsigned char)*text); break;
            case 'D': matches = *text && !isdigit((unsigned char)*text); break;
            case 'w': matches = isalnum((unsigned char)*text) || *text == '_'; break;
            case 'W': matches = *text && !isalnum((unsigned char)*text) && *text != '_'; break;
            default:  matches = (*text == re[1]); break;
        }
        if (re[2] == '*') return regex_match_star(re[1], re+3, text);
        if (re[2] == '+') return regex_match_plus(re[1], re+3, text);
        if (re[2] == '?') {
            if (matches && regex_match_here(re+3, text+1)) return 1;
            return regex_match_here(re+3, text);
        }
        return matches && regex_match_here(re+2, text+1);
    }

    if (re[0] == '[') {
        int adv = 0;
        int m = regex_char_in_class(re+1, *text, &adv);
        const char* after_class = re + 1 + adv;
        if (*after_class == '*') return regex_match_star('.', after_class+1, text);
        if (*after_class == '+') return regex_match_plus('.', after_class+1, text);
        if (*after_class == '?') {
            if (m && *text && regex_match_here(after_class+1, text+1)) return 1;
            return regex_match_here(after_class+1, text);
        }
        return *text && m && regex_match_here(after_class, text+1);
    }

    if (re[1] == '*') return regex_match_star(re[0], re+2, text);
    if (re[1] == '+') return regex_match_plus(re[0], re+2, text);
    if (re[1] == '?') {
        if ((*text == re[0] || re[0] == '.') && *text && regex_match_here(re+2, text+1)) return 1;
        return regex_match_here(re+2, text);
    }
    if ((re[0] == '.' && *text) || re[0] == *text)
        return regex_match_here(re+1, text+1);
    return 0;
}

xc_bool_t xc_string_matches(xc_string_t s, const char* pattern) {
    /* Null-terminate the string for regex matching */
    char* text = (char*)malloc(s.len + 1);
    if (!text) return false;
    memcpy(text, s.data, s.len);
    text[s.len] = '\0';

    int result = 0;
    if (pattern[0] == '^') {
        result = regex_match_here(pattern+1, text);
    } else {
        /* Try at each position */
        const char* t = text;
        do {
            if (regex_match_here(pattern, t)) { result = 1; break; }
        } while (*t++ != '\0');
    }
    free(text);
    return (xc_bool_t)result;
}

/* ─── File I/O ───────────────────────────────────────────────────────────── */

xc_string_t file_read_all(xc_string_t path) {
    char* cpath = xc_string_to_cstr(path);
    FILE* fp = fopen(cpath, "rb");
    free(cpath);
    if (!fp) {
        fprintf(stderr, "xc: cannot open file: ");
        fwrite(path.data, 1, path.len, stderr);
        fprintf(stderr, "\n");
        abort();
    }
    if (fseek(fp, 0, SEEK_END) != 0) abort();
    long size = ftell(fp);
    if (size < 0) abort();
    rewind(fp);
    char* buf = (char*)malloc((size_t)size + 1);
    if (!buf) abort();
    (void)fread(buf, 1, (size_t)size, fp);
    buf[size] = '\0';
    fclose(fp);
    return (xc_string_t){ .data = buf, .len = (xc_size_t)size };
}

/* ─── Diagnostics ────────────────────────────────────────────────────────── */

static char xc_diag_file[4096] = "<input>";

void diag_set_file(xc_string_t path) {
    size_t n = path.len < sizeof(xc_diag_file) - 1 ? path.len : sizeof(xc_diag_file) - 1;
    if (n) memcpy(xc_diag_file, path.data, n);
    xc_diag_file[n] = '\0';
}

void diag_error(xc_integer_t line, xc_string_t msg) {
    fprintf(stderr, "xc: %s:%lld: error: %.*s\n",
            xc_diag_file, (long long)line, (int)msg.len, msg.data);
    exit(1);
}

xc_bool_t file_write(xc_string_t path, xc_string_t content) {
    char* cpath = xc_string_to_cstr(path);
    FILE* fp = fopen(cpath, "w");
    free(cpath);
    if (!fp) return false;
    fwrite(content.data, 1, content.len, fp);
    fclose(fp);
    return true;
}

xc_bool_t file_writeln(xc_string_t path, xc_string_t line) {
    char* cpath = xc_string_to_cstr(path);
    FILE* fp = fopen(cpath, "a");
    free(cpath);
    if (!fp) return false;
    fwrite(line.data, 1, line.len, fp);
    fputc('\n', fp);
    fclose(fp);
    return true;
}

/* ─── REPL / tooling helpers ─────────────────────────────────────────────── */

static int g_stdin_eof = 0;

/* Read one line from stdin (newline stripped). Sets the EOF flag on end. */
xc_string_t read_line(void) {
    char buf[16384];
    if (!fgets(buf, sizeof(buf), stdin)) {
        g_stdin_eof = 1;
        return (xc_string_t){ .data = "", .len = 0 };
    }
    size_t n = strlen(buf);
    if (n && buf[n-1] == '\n') buf[--n] = '\0';
    char* c = (char*)malloc(n + 1);
    if (!c) abort();
    memcpy(c, buf, n + 1);
    return (xc_string_t){ .data = c, .len = n };
}

xc_bool_t stdin_eof(void) { return (xc_bool_t)g_stdin_eof; }

void flush_out(void) { fflush(stdout); }

/* Run a shell command; return 0 on success, 1 otherwise. */
xc_integer_t run_command(xc_string_t cmd) {
    char* c = xc_string_to_cstr(cmd);
    int rc = system(c);
    free(c);
    return (xc_integer_t)(rc == 0 ? 0 : 1);
}

/* Read an environment variable, or the given default if unset/empty. */
xc_string_t get_env(xc_string_t name, xc_string_t dflt) {
    char* nm = xc_string_to_cstr(name);
    const char* v = getenv(nm);
    free(nm);
    if (!v || !v[0]) return dflt;
    return xc_string_from_cstr(strdup(v));
}

/* ─── String helpers (non-inline) ────────────────────────────────────────── */

xc_string_t xc_string_substring(xc_string_t s, xc_size_t from, xc_size_t to) {
    if (from > s.len) from = s.len;
    if (to > s.len) to = s.len;
    if (from > to) to = from;
    return xc_string_from_buf(s.data + from, to - from);
}

xc_string_t xc_string_trim(xc_string_t s) {
    const char* p = s.data;
    const char* end = s.data + s.len;
    while (p < end && isspace((unsigned char)*p)) p++;
    while (end > p && isspace((unsigned char)*(end-1))) end--;
    return xc_string_from_buf(p, (xc_size_t)(end - p));
}

xc_bool_t xc_string_starts_with(xc_string_t s, xc_string_t prefix) {
    if (prefix.len > s.len) return false;
    return memcmp(s.data, prefix.data, prefix.len) == 0;
}

xc_bool_t xc_string_ends_with(xc_string_t s, xc_string_t suffix) {
    if (suffix.len > s.len) return false;
    return memcmp(s.data + s.len - suffix.len, suffix.data, suffix.len) == 0;
}

xc_bool_t xc_string_contains(xc_string_t haystack, xc_string_t needle) {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    for (xc_size_t i = 0; i + needle.len <= haystack.len; i++) {
        if (memcmp(haystack.data + i, needle.data, needle.len) == 0) return true;
    }
    return false;
}

/* ─── String + number conversion ─────────────────────────────────────────── */

xc_opt_number_t xc_parse_number(xc_string_t s) {
    char* buf = xc_string_to_cstr(s);
    char* end;
    errno = 0;
    double val = strtod(buf, &end);
    free(buf);
    if (errno != 0 || end == buf) return (xc_opt_number_t){ .has_value = false };
    return (xc_opt_number_t){ .has_value = true, .value = val };
}

xc_opt_integer_t xc_parse_integer(xc_string_t s) {
    char* buf = xc_string_to_cstr(s);
    char* end;
    errno = 0;
    long long val = strtoll(buf, &end, 10);
    free(buf);
    if (errno != 0 || end == buf) return (xc_opt_integer_t){ .has_value = false };
    return (xc_opt_integer_t){ .has_value = true, .value = (xc_integer_t)val };
}

/* ─── Standard library primitives (xstd_*) ──────────────────────────────────
 * Clean, X-friendly signatures (Integer/Number/Bool/String) wrapping libc/libm
 * and the existing runtime, so the X-source stdlib in std/*.x can extern them. */
#include <time.h>

/* math */
xc_number_t xstd_sqrt (xc_number_t x)              { return sqrt(x); }
xc_number_t xstd_pow  (xc_number_t x, xc_number_t y){ return pow(x, y); }
xc_number_t xstd_exp  (xc_number_t x)              { return exp(x); }
xc_number_t xstd_ln   (xc_number_t x)              { return log(x); }
xc_number_t xstd_log10(xc_number_t x)              { return log10(x); }
xc_number_t xstd_sin  (xc_number_t x)              { return sin(x); }
xc_number_t xstd_cos  (xc_number_t x)              { return cos(x); }
xc_number_t xstd_tan  (xc_number_t x)              { return tan(x); }
xc_number_t xstd_floor(xc_number_t x)              { return floor(x); }
xc_number_t xstd_ceil (xc_number_t x)              { return ceil(x); }
xc_number_t xstd_round(xc_number_t x)              { return round(x); }
xc_number_t xstd_fabs (xc_number_t x)              { return fabs(x); }
xc_number_t xstd_pi   (void)                       { return 3.14159265358979323846; }
xc_number_t xstd_e    (void)                       { return 2.71828182845904523536; }

/* text */
xc_integer_t xstd_strlen(xc_string_t s) { return (xc_integer_t)s.len; }

xc_integer_t xstd_char_at(xc_string_t s, xc_integer_t i) {
    if (i < 0 || (xc_size_t)i >= s.len) return -1;
    return (xc_integer_t)(unsigned char)s.data[i];
}

xc_string_t xstd_substring(xc_string_t s, xc_integer_t from, xc_integer_t to) {
    if (from < 0) from = 0;
    if (to > (xc_integer_t)s.len) to = (xc_integer_t)s.len;
    if (from >= to) return (xc_string_t){ .data = "", .len = 0 };
    xc_size_t n = (xc_size_t)(to - from);
    char* b = (char*)malloc(n + 1);
    if (!b) abort();
    memcpy(b, s.data + from, n); b[n] = '\0';
    return (xc_string_t){ .data = b, .len = n };
}

xc_string_t xstd_trim(xc_string_t s) {
    xc_size_t a = 0, b = s.len;
    while (a < b && isspace((unsigned char)s.data[a])) a++;
    while (b > a && isspace((unsigned char)s.data[b-1])) b--;
    return xstd_substring(s, (xc_integer_t)a, (xc_integer_t)b);
}

xc_bool_t xstd_starts_with(xc_string_t s, xc_string_t p) {
    if (p.len > s.len) return false;
    return memcmp(s.data, p.data, p.len) == 0;
}
xc_bool_t xstd_ends_with(xc_string_t s, xc_string_t p) {
    if (p.len > s.len) return false;
    return memcmp(s.data + s.len - p.len, p.data, p.len) == 0;
}
xc_integer_t xstd_index_of(xc_string_t s, xc_string_t n) {
    if (n.len == 0) return 0;
    if (n.len > s.len) return -1;
    for (xc_size_t i = 0; i + n.len <= s.len; i++)
        if (memcmp(s.data + i, n.data, n.len) == 0) return (xc_integer_t)i;
    return -1;
}
xc_bool_t xstd_contains(xc_string_t s, xc_string_t n) { return xstd_index_of(s, n) >= 0; }

xc_string_t xstd_to_upper(xc_string_t s) {
    char* b = (char*)malloc(s.len + 1); if (!b) abort();
    for (xc_size_t i = 0; i < s.len; i++) b[i] = (char)toupper((unsigned char)s.data[i]);
    b[s.len] = '\0';
    return (xc_string_t){ .data = b, .len = s.len };
}
xc_string_t xstd_to_lower(xc_string_t s) {
    char* b = (char*)malloc(s.len + 1); if (!b) abort();
    for (xc_size_t i = 0; i < s.len; i++) b[i] = (char)tolower((unsigned char)s.data[i]);
    b[s.len] = '\0';
    return (xc_string_t){ .data = b, .len = s.len };
}
xc_string_t xstd_repeat(xc_string_t s, xc_integer_t n) {
    if (n <= 0) return (xc_string_t){ .data = "", .len = 0 };
    xc_size_t total = s.len * (xc_size_t)n;
    char* b = (char*)malloc(total + 1); if (!b) abort();
    for (xc_integer_t i = 0; i < n; i++) memcpy(b + i * s.len, s.data, s.len);
    b[total] = '\0';
    return (xc_string_t){ .data = b, .len = total };
}
xc_string_t xstd_replace(xc_string_t s, xc_string_t a, xc_string_t b) {
    if (a.len == 0) return s;
    /* count occurrences */
    xc_size_t count = 0;
    for (xc_size_t i = 0; i + a.len <= s.len; ) {
        if (memcmp(s.data + i, a.data, a.len) == 0) { count++; i += a.len; } else i++;
    }
    if (count == 0) return s;
    xc_size_t out_len = s.len + count * (b.len > a.len ? (b.len - a.len) : 0)
                              - count * (a.len > b.len ? (a.len - b.len) : 0);
    char* out = (char*)malloc(out_len + 1); if (!out) abort();
    xc_size_t oi = 0;
    for (xc_size_t i = 0; i < s.len; ) {
        if (i + a.len <= s.len && memcmp(s.data + i, a.data, a.len) == 0) {
            memcpy(out + oi, b.data, b.len); oi += b.len; i += a.len;
        } else out[oi++] = s.data[i++];
    }
    out[oi] = '\0';
    return (xc_string_t){ .data = out, .len = oi };
}

/* Heap-copy a byte range into a fresh NUL-terminated xc_string_t. */
static xc_string_t xc_str_copy(const char* p, xc_size_t n) {
    char* buf = (char*)malloc(n + 1); if (!buf) abort();
    if (n) memcpy(buf, p, n);
    buf[n] = '\0';
    return (xc_string_t){ .data = buf, .len = n };
}

xc_arr_string_t xstd_split(xc_string_t s, xc_string_t sep) {
    xc_arr_string_t out = { NULL, 0, 0 };
    if (sep.len == 0) {                 /* empty separator -> [s] */
        out.data = (xc_string_t*)malloc(sizeof(xc_string_t)); if (!out.data) abort();
        out.data[0] = xc_str_copy(s.data, s.len); out.len = 1; out.cap = 1;
        return out;
    }
    xc_size_t count = 1;                /* pieces = occurrences + 1 */
    for (xc_size_t i = 0; i + sep.len <= s.len; ) {
        if (memcmp(s.data + i, sep.data, sep.len) == 0) { count++; i += sep.len; } else i++;
    }
    out.data = (xc_string_t*)malloc(count * sizeof(xc_string_t)); if (!out.data) abort();
    out.cap = count;
    xc_size_t start = 0, idx = 0;
    for (xc_size_t i = 0; i + sep.len <= s.len; ) {
        if (memcmp(s.data + i, sep.data, sep.len) == 0) {
            out.data[idx++] = xc_str_copy(s.data + start, i - start);
            i += sep.len; start = i;
        } else i++;
    }
    out.data[idx++] = xc_str_copy(s.data + start, s.len - start);
    out.len = idx;
    return out;
}

xc_string_t xstd_join(xc_arr_string_t parts, xc_string_t sep) {
    if (parts.len == 0) return xc_str_copy("", 0);
    xc_size_t total = 0;
    for (xc_size_t i = 0; i < parts.len; i++) total += parts.data[i].len;
    total += sep.len * (parts.len - 1);
    char* buf = (char*)malloc(total + 1); if (!buf) abort();
    xc_size_t oi = 0;
    for (xc_size_t i = 0; i < parts.len; i++) {
        if (i) { memcpy(buf + oi, sep.data, sep.len); oi += sep.len; }
        memcpy(buf + oi, parts.data[i].data, parts.data[i].len); oi += parts.data[i].len;
    }
    buf[oi] = '\0';
    return (xc_string_t){ .data = buf, .len = oi };
}

/* convert / parse */
xc_bool_t xstd_num_ok(xc_string_t s) {
    char* buf = xc_string_to_cstr(s); char* e; errno = 0;
    (void)strtod(buf, &e);
    xc_bool_t ok = (errno == 0 && e != buf && *e == '\0' && s.len > 0);
    free(buf); return ok;
}
xc_number_t xstd_to_number(xc_string_t s) {
    char* buf = xc_string_to_cstr(s); double v = strtod(buf, NULL); free(buf); return v;
}
xc_bool_t xstd_int_ok(xc_string_t s) {
    char* buf = xc_string_to_cstr(s); char* e; errno = 0;
    (void)strtoll(buf, &e, 10);
    xc_bool_t ok = (errno == 0 && e != buf && *e == '\0' && s.len > 0);
    free(buf); return ok;
}
xc_integer_t xstd_to_integer(xc_string_t s) {
    char* buf = xc_string_to_cstr(s); long long v = strtoll(buf, NULL, 10); free(buf);
    return (xc_integer_t)v;
}

/* filesystem */
xc_bool_t xstd_file_exists(xc_string_t path) {
    char* p = xc_string_to_cstr(path); FILE* f = fopen(p, "rb"); free(p);
    if (f) { fclose(f); return true; }
    return false;
}

/* process */
void xstd_exit(xc_integer_t code) { exit((int)code); }

/* time */
xc_integer_t xstd_now_nanos(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (xc_integer_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}
void xstd_sleep_ms(xc_integer_t ms) {
    if (ms < 0) return;
    struct timespec ts; ts.tv_sec = ms / 1000; ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}
