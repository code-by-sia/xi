/*
 * runtime.c — X language runtime support implementation
 *
 * Contains functions that cannot be inlined in the header.
 */
#include "runtime.h"
#include <ctype.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

static xc_string_t xc_str_copy(const char* p, xc_size_t n);  /* defined below */

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

/* ─── Interrupts ─────────────────────────────────────────────────────────── */

xc_handler_t* xc_handlers = NULL;

xc_handler_t* xc_int_find(int type_id) {
    xc_handler_t* h = xc_handlers;
    while (h) { if (h->type_id == type_id) return h; h = h->prev; }
    return NULL;
}

void xc_int_unhandled(const char* name) {
    fprintf(stderr, "xc: unhandled interrupt: %s\n", name);
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

/* ─── Filesystem ─────────────────────────────────────────────────────────── */

xc_bytes_t xstd_read_bytes(xc_string_t path) {
    char* cpath = xc_string_to_cstr(path);
    FILE* fp = fopen(cpath, "rb");
    free(cpath);
    if (!fp) return bytes_empty();
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return bytes_empty(); }
    long size = ftell(fp);
    if (size < 0) { fclose(fp); return bytes_empty(); }
    rewind(fp);
    unsigned char* buf = (unsigned char*)malloc((size_t)size ? (size_t)size : 1);
    if (!buf) abort();
    (void)fread(buf, 1, (size_t)size, fp);
    fclose(fp);
    return (xc_bytes_t){ .data = buf, .len = (xc_size_t)size };
}

xc_bool_t xstd_write_bytes(xc_string_t path, xc_bytes_t b) {
    char* cpath = xc_string_to_cstr(path);
    FILE* fp = fopen(cpath, "wb");
    free(cpath);
    if (!fp) return false;
    if (b.len) fwrite(b.data, 1, b.len, fp);
    fclose(fp);
    return true;
}

xc_bool_t xstd_is_dir(xc_string_t path) {
    char* p = xc_string_to_cstr(path); struct stat st; int r = stat(p, &st); free(p);
    return r == 0 && S_ISDIR(st.st_mode);
}

xc_bool_t xstd_is_file(xc_string_t path) {
    char* p = xc_string_to_cstr(path); struct stat st; int r = stat(p, &st); free(p);
    return r == 0 && S_ISREG(st.st_mode);
}

xc_integer_t xstd_file_size(xc_string_t path) {
    char* p = xc_string_to_cstr(path); struct stat st; int r = stat(p, &st); free(p);
    return r == 0 ? (xc_integer_t)st.st_size : -1;
}

xc_integer_t xstd_mtime(xc_string_t path) {
    char* p = xc_string_to_cstr(path); struct stat st; int r = stat(p, &st); free(p);
    return r == 0 ? (xc_integer_t)st.st_mtime : -1;
}

xc_bool_t xstd_remove(xc_string_t path) {
    char* p = xc_string_to_cstr(path);
    int r = remove(p);            /* removes files and empty dirs */
    free(p);
    return r == 0;
}

xc_bool_t xstd_rename(xc_string_t from, xc_string_t to) {
    char* a = xc_string_to_cstr(from); char* b = xc_string_to_cstr(to);
    int r = rename(a, b);
    free(a); free(b);
    return r == 0;
}

xc_bool_t xstd_mkdir(xc_string_t path) {
    char* p = xc_string_to_cstr(path);
    int r = mkdir(p, 0777);
    free(p);
    return r == 0;
}

xc_bool_t xstd_mkdir_all(xc_string_t path) {
    char* p = xc_string_to_cstr(path);
    int ok = 1;
    for (char* s = p + 1; *s; s++) {
        if (*s == '/') {
            *s = '\0';
            if (mkdir(p, 0777) != 0 && errno != EEXIST) { ok = 0; break; }
            *s = '/';
        }
    }
    if (ok && mkdir(p, 0777) != 0 && errno != EEXIST) ok = 0;
    free(p);
    return ok != 0;
}

xc_string_t xstd_cwd(void) {
    char buf[4096];
    if (getcwd(buf, sizeof(buf))) return xc_str_copy(buf, strlen(buf));
    return xc_str_copy("", 0);
}

/* Directory entries (excluding "." and ".."), as String[]. Empty if not a dir. */
xc_arr_string_t xstd_list_dir(xc_string_t path) {
    xc_arr_string_t out = { NULL, 0, 0 };
    char* p = xc_string_to_cstr(path);
    DIR* d = opendir(p);
    free(p);
    if (!d) return out;
    struct dirent* e;
    while ((e = readdir(d)) != NULL) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        if (out.len == out.cap) {
            xc_size_t nc = out.cap ? out.cap * 2 : 8;
            out.data = (xc_string_t*)realloc(out.data, nc * sizeof(xc_string_t));
            if (!out.data) abort();
            out.cap = nc;
        }
        out.data[out.len++] = xc_str_copy(e->d_name, strlen(e->d_name));
    }
    closedir(d);
    return out;
}

/* ─── Networking (TCP, blocking) ─────────────────────────────────────────── */

xc_integer_t xstd_tcp_connect(xc_string_t host, xc_integer_t port) {
    char* h = xc_string_to_cstr(host);
    char portstr[16]; snprintf(portstr, sizeof(portstr), "%ld", (long)port);
    struct addrinfo hints, *res, *rp;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
    int gai = getaddrinfo(h, portstr, &hints, &res);
    free(h);
    if (gai != 0) return -1;
    int fd = -1;
    for (rp = res; rp; rp = rp->ai_next) {
        fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (fd < 0) continue;
        if (connect(fd, rp->ai_addr, rp->ai_addrlen) == 0) break;
        close(fd); fd = -1;
    }
    freeaddrinfo(res);
    return (xc_integer_t)fd;
}

xc_integer_t xstd_tcp_listen(xc_integer_t port, xc_integer_t backlog) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((unsigned short)port);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) { close(fd); return -1; }
    if (listen(fd, (int)backlog) != 0) { close(fd); return -1; }
    return (xc_integer_t)fd;
}

xc_integer_t xstd_tcp_accept(xc_integer_t fd) {
    return (xc_integer_t)accept((int)fd, NULL, NULL);
}

/* The local port a socket is bound to (useful after listening on port 0). */
xc_integer_t xstd_sock_port(xc_integer_t fd) {
    struct sockaddr_in addr; socklen_t len = sizeof(addr);
    if (getsockname((int)fd, (struct sockaddr*)&addr, &len) != 0) return -1;
    return (xc_integer_t)ntohs(addr.sin_port);
}

xc_integer_t xstd_sock_send(xc_integer_t fd, xc_bytes_t data) {
    return (xc_integer_t)send((int)fd, data.data, data.len, 0);
}

xc_bytes_t xstd_sock_recv(xc_integer_t fd, xc_integer_t max) {
    if (max <= 0) return bytes_empty();
    unsigned char* buf = (unsigned char*)malloc((size_t)max);
    if (!buf) abort();
    ssize_t n = recv((int)fd, buf, (size_t)max, 0);
    if (n <= 0) { free(buf); return bytes_empty(); }
    return (xc_bytes_t){ .data = buf, .len = (xc_size_t)n };
}

xc_bool_t xstd_sock_close(xc_integer_t fd) {
    return close((int)fd) == 0;
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

/* ─── JSON (std/json — serialization) ────────────────────────────────────────
 * A small, self-contained JSON DOM: build values programmatically, stringify
 * them, and parse text back into a tree. Referenced from X as the `Json` type.
 */
enum { XJ_NULL = 0, XJ_BOOL = 1, XJ_NUMBER = 2, XJ_STRING = 3,
       XJ_ARRAY = 4, XJ_OBJECT = 5, XJ_ERROR = 6 };

struct xc_json_node {
    int kind;
    xc_bool_t b;          /* XJ_BOOL   */
    xc_number_t num;      /* XJ_NUMBER */
    char* str;            /* XJ_STRING (NUL-terminated, owned) */
    struct xc_json_node** items;  /* XJ_ARRAY / XJ_OBJECT values */
    char** keys;                  /* XJ_OBJECT keys (parallel to items) */
    long len, cap;
};

static struct xc_json_node* xj_alloc(int kind) {
    struct xc_json_node* n = (struct xc_json_node*)calloc(1, sizeof(*n));
    if (!n) abort();
    n->kind = kind;
    return n;
}

xc_Json_t xstd_json_null(void)            { return xj_alloc(XJ_NULL); }
xc_Json_t xstd_json_bool(xc_bool_t v)     { struct xc_json_node* n = xj_alloc(XJ_BOOL); n->b = v; return n; }
xc_Json_t xstd_json_number(xc_number_t v) { struct xc_json_node* n = xj_alloc(XJ_NUMBER); n->num = v; return n; }
xc_Json_t xstd_json_array(void)           { return xj_alloc(XJ_ARRAY); }
xc_Json_t xstd_json_object(void)          { return xj_alloc(XJ_OBJECT); }

static char* xj_strdup_n(const char* p, size_t n) {
    char* s = (char*)malloc(n + 1); if (!s) abort();
    if (n) memcpy(s, p, n);
    s[n] = '\0';
    return s;
}
xc_Json_t xstd_json_string(xc_string_t v) {
    struct xc_json_node* n = xj_alloc(XJ_STRING);
    n->str = xj_strdup_n(v.data, v.len);
    return n;
}

static void xj_grow(struct xc_json_node* c) {
    if (c->len < c->cap) return;
    long ncap = c->cap ? c->cap * 2 : 4;
    c->items = (struct xc_json_node**)realloc(c->items, (size_t)ncap * sizeof(*c->items));
    c->keys  = (char**)realloc(c->keys, (size_t)ncap * sizeof(*c->keys));
    if (!c->items || !c->keys) abort();
    c->cap = ncap;
}

xc_Json_t xstd_json_push(xc_Json_t arr, xc_Json_t v) {
    if (!arr || arr->kind != XJ_ARRAY) return arr;
    xj_grow(arr);
    arr->keys[arr->len] = NULL;
    arr->items[arr->len] = v;
    arr->len++;
    return arr;
}

xc_Json_t xstd_json_set(xc_Json_t obj, xc_string_t key, xc_Json_t v) {
    if (!obj || obj->kind != XJ_OBJECT) return obj;
    char* k = xj_strdup_n(key.data, key.len);
    for (long i = 0; i < obj->len; i++) {       /* replace existing key */
        if (strcmp(obj->keys[i], k) == 0) { obj->items[i] = v; free(k); return obj; }
    }
    xj_grow(obj);
    obj->keys[obj->len] = k;
    obj->items[obj->len] = v;
    obj->len++;
    return obj;
}

/* introspection */
xc_integer_t xstd_json_kind(xc_Json_t v)   { return v ? (xc_integer_t)v->kind : XJ_ERROR; }
xc_integer_t xstd_json_length(xc_Json_t v) { return (v && (v->kind == XJ_ARRAY || v->kind == XJ_OBJECT)) ? (xc_integer_t)v->len : 0; }
xc_bool_t    xstd_json_ok(xc_Json_t v)     { return v && v->kind != XJ_ERROR; }

xc_Json_t xstd_json_at(xc_Json_t arr, xc_integer_t i) {
    if (!arr || arr->kind != XJ_ARRAY || i < 0 || i >= arr->len) return xstd_json_null();
    return arr->items[i];
}
xc_Json_t xstd_json_get(xc_Json_t obj, xc_string_t key) {
    if (!obj || obj->kind != XJ_OBJECT) return xstd_json_null();
    for (long i = 0; i < obj->len; i++)
        if (strlen(obj->keys[i]) == key.len && memcmp(obj->keys[i], key.data, key.len) == 0)
            return obj->items[i];
    return xstd_json_null();
}
xc_bool_t xstd_json_has(xc_Json_t obj, xc_string_t key) {
    if (!obj || obj->kind != XJ_OBJECT) return false;
    for (long i = 0; i < obj->len; i++)
        if (strlen(obj->keys[i]) == key.len && memcmp(obj->keys[i], key.data, key.len) == 0)
            return true;
    return false;
}
xc_string_t xstd_json_key_at(xc_Json_t obj, xc_integer_t i) {
    if (!obj || obj->kind != XJ_OBJECT || i < 0 || i >= obj->len) return xc_str_copy("", 0);
    return xc_str_copy(obj->keys[i], strlen(obj->keys[i]));
}
xc_string_t xstd_json_as_string(xc_Json_t v) {
    if (v && v->kind == XJ_STRING && v->str) return xc_str_copy(v->str, strlen(v->str));
    return xc_str_copy("", 0);
}
xc_number_t xstd_json_as_number(xc_Json_t v) { return (v && v->kind == XJ_NUMBER) ? v->num : 0.0; }
xc_bool_t   xstd_json_as_bool(xc_Json_t v)   { return (v && v->kind == XJ_BOOL) ? v->b : false; }

/* ── stringify ── */
typedef struct { char* buf; size_t len, cap; } xj_sb;
static void xj_sb_putn(xj_sb* s, const char* p, size_t n) {
    if (s->len + n + 1 > s->cap) {
        size_t nc = s->cap ? s->cap : 64;
        while (s->len + n + 1 > nc) nc *= 2;
        s->buf = (char*)realloc(s->buf, nc); if (!s->buf) abort();
        s->cap = nc;
    }
    memcpy(s->buf + s->len, p, n); s->len += n; s->buf[s->len] = '\0';
}
static void xj_sb_put(xj_sb* s, const char* p) { xj_sb_putn(s, p, strlen(p)); }
static void xj_sb_putc(xj_sb* s, char c) { xj_sb_putn(s, &c, 1); }
static void xj_write_string(xj_sb* s, const char* p, size_t n) {
    xj_sb_putc(s, '"');
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)p[i];
        switch (c) {
            case '"':  xj_sb_put(s, "\\\""); break;
            case '\\': xj_sb_put(s, "\\\\"); break;
            case '\n': xj_sb_put(s, "\\n");  break;
            case '\t': xj_sb_put(s, "\\t");  break;
            case '\r': xj_sb_put(s, "\\r");  break;
            case '\b': xj_sb_put(s, "\\b");  break;
            case '\f': xj_sb_put(s, "\\f");  break;
            default:
                if (c < 0x20) { char u[8]; snprintf(u, sizeof(u), "\\u%04x", c); xj_sb_put(s, u); }
                else xj_sb_putc(s, (char)c);
        }
    }
    xj_sb_putc(s, '"');
}
static void xj_write(xj_sb* s, struct xc_json_node* v, int pretty, int depth) {
    if (!v) { xj_sb_put(s, "null"); return; }
    switch (v->kind) {
        case XJ_NULL:  xj_sb_put(s, "null"); break;
        case XJ_BOOL:  xj_sb_put(s, v->b ? "true" : "false"); break;
        case XJ_NUMBER: {
            char buf[64];
            if (v->num == (xc_integer_t)v->num) snprintf(buf, sizeof(buf), "%lld", (long long)(xc_integer_t)v->num);
            else snprintf(buf, sizeof(buf), "%g", v->num);
            xj_sb_put(s, buf);
            break;
        }
        case XJ_STRING: xj_write_string(s, v->str ? v->str : "", v->str ? strlen(v->str) : 0); break;
        case XJ_ARRAY:
        case XJ_OBJECT: {
            int obj = (v->kind == XJ_OBJECT);
            xj_sb_putc(s, obj ? '{' : '[');
            for (long i = 0; i < v->len; i++) {
                if (i) xj_sb_putc(s, ',');
                if (pretty) { xj_sb_putc(s, '\n'); for (int d = 0; d <= depth; d++) xj_sb_put(s, "  "); }
                if (obj) { xj_write_string(s, v->keys[i], strlen(v->keys[i])); xj_sb_put(s, pretty ? ": " : ":"); }
                xj_write(s, v->items[i], pretty, depth + 1);
            }
            if (pretty && v->len) { xj_sb_putc(s, '\n'); for (int d = 0; d < depth; d++) xj_sb_put(s, "  "); }
            xj_sb_putc(s, obj ? '}' : ']');
            break;
        }
        default: xj_sb_put(s, "null");
    }
}
xc_string_t xstd_json_stringify(xc_Json_t v) {
    xj_sb s = { NULL, 0, 0 }; xj_write(&s, v, 0, 0);
    if (!s.buf) return xc_str_copy("", 0);
    return (xc_string_t){ .data = s.buf, .len = s.len };
}
xc_string_t xstd_json_pretty(xc_Json_t v) {
    xj_sb s = { NULL, 0, 0 }; xj_write(&s, v, 1, 0);
    if (!s.buf) return xc_str_copy("", 0);
    return (xc_string_t){ .data = s.buf, .len = s.len };
}

/* ── parse ── */
typedef struct { const char* p; const char* end; int err; } xj_parser;
static void xj_skip_ws(xj_parser* P) {
    while (P->p < P->end && (*P->p == ' ' || *P->p == '\t' || *P->p == '\n' || *P->p == '\r')) P->p++;
}
static struct xc_json_node* xj_parse_value(xj_parser* P);
static char* xj_parse_raw_string(xj_parser* P, size_t* outn) {
    /* assumes *P->p == '"' */
    P->p++;
    xj_sb s = { NULL, 0, 0 };
    while (P->p < P->end && *P->p != '"') {
        char c = *P->p++;
        if (c == '\\' && P->p < P->end) {
            char e = *P->p++;
            switch (e) {
                case 'n': xj_sb_putc(&s, '\n'); break;
                case 't': xj_sb_putc(&s, '\t'); break;
                case 'r': xj_sb_putc(&s, '\r'); break;
                case 'b': xj_sb_putc(&s, '\b'); break;
                case 'f': xj_sb_putc(&s, '\f'); break;
                case '/': xj_sb_putc(&s, '/');  break;
                case '"': xj_sb_putc(&s, '"');  break;
                case '\\': xj_sb_putc(&s, '\\'); break;
                case 'u': {
                    if (P->end - P->p >= 4) {
                        char h[5]; memcpy(h, P->p, 4); h[4] = '\0'; P->p += 4;
                        unsigned cp = (unsigned)strtol(h, NULL, 16);
                        if (cp < 0x80) xj_sb_putc(&s, (char)cp);
                        else if (cp < 0x800) { char u[2] = { (char)(0xC0|(cp>>6)), (char)(0x80|(cp&0x3F)) }; xj_sb_putn(&s, u, 2); }
                        else { char u[3] = { (char)(0xE0|(cp>>12)), (char)(0x80|((cp>>6)&0x3F)), (char)(0x80|(cp&0x3F)) }; xj_sb_putn(&s, u, 3); }
                    }
                    break;
                }
                default: xj_sb_putc(&s, e);
            }
        } else { xj_sb_putc(&s, c); }
    }
    if (P->p < P->end && *P->p == '"') P->p++; else P->err = 1;
    if (!s.buf) { s.buf = xj_strdup_n("", 0); s.len = 0; }
    *outn = s.len;
    return s.buf;
}
static struct xc_json_node* xj_parse_value(xj_parser* P) {
    xj_skip_ws(P);
    if (P->p >= P->end) { P->err = 1; return xj_alloc(XJ_ERROR); }
    char c = *P->p;
    if (c == '"') {
        size_t n; char* str = xj_parse_raw_string(P, &n);
        struct xc_json_node* node = xj_alloc(XJ_STRING); node->str = str; return node;
    }
    if (c == '{') {
        P->p++;
        struct xc_json_node* obj = xj_alloc(XJ_OBJECT);
        xj_skip_ws(P);
        if (P->p < P->end && *P->p == '}') { P->p++; return obj; }
        while (P->p < P->end) {
            xj_skip_ws(P);
            if (*P->p != '"') { P->err = 1; break; }
            size_t kn; char* key = xj_parse_raw_string(P, &kn);
            xj_skip_ws(P);
            if (P->p < P->end && *P->p == ':') P->p++; else { P->err = 1; free(key); break; }
            struct xc_json_node* val = xj_parse_value(P);
            xj_grow(obj); obj->keys[obj->len] = key; obj->items[obj->len] = val; obj->len++;
            xj_skip_ws(P);
            if (P->p < P->end && *P->p == ',') { P->p++; continue; }
            if (P->p < P->end && *P->p == '}') { P->p++; break; }
            P->err = 1; break;
        }
        return obj;
    }
    if (c == '[') {
        P->p++;
        struct xc_json_node* arr = xj_alloc(XJ_ARRAY);
        xj_skip_ws(P);
        if (P->p < P->end && *P->p == ']') { P->p++; return arr; }
        while (P->p < P->end) {
            struct xc_json_node* val = xj_parse_value(P);
            xj_grow(arr); arr->keys[arr->len] = NULL; arr->items[arr->len] = val; arr->len++;
            xj_skip_ws(P);
            if (P->p < P->end && *P->p == ',') { P->p++; continue; }
            if (P->p < P->end && *P->p == ']') { P->p++; break; }
            P->err = 1; break;
        }
        return arr;
    }
    if (c == 't') { if (P->end - P->p >= 4 && memcmp(P->p, "true", 4) == 0)  { P->p += 4; struct xc_json_node* n = xj_alloc(XJ_BOOL); n->b = true; return n; } P->err = 1; return xj_alloc(XJ_ERROR); }
    if (c == 'f') { if (P->end - P->p >= 5 && memcmp(P->p, "false", 5) == 0) { P->p += 5; struct xc_json_node* n = xj_alloc(XJ_BOOL); n->b = false; return n; } P->err = 1; return xj_alloc(XJ_ERROR); }
    if (c == 'n') { if (P->end - P->p >= 4 && memcmp(P->p, "null", 4) == 0)  { P->p += 4; return xj_alloc(XJ_NULL); } P->err = 1; return xj_alloc(XJ_ERROR); }
    if (c == '-' || (c >= '0' && c <= '9')) {
        const char* start = P->p;
        if (*P->p == '-') P->p++;
        while (P->p < P->end && ((*P->p >= '0' && *P->p <= '9') || *P->p == '.' || *P->p == 'e' || *P->p == 'E' || *P->p == '+' || *P->p == '-')) P->p++;
        char* tmp = xj_strdup_n(start, (size_t)(P->p - start));
        struct xc_json_node* n = xj_alloc(XJ_NUMBER); n->num = strtod(tmp, NULL); free(tmp);
        return n;
    }
    P->err = 1; return xj_alloc(XJ_ERROR);
}
xc_Json_t xstd_json_parse(xc_string_t s) {
    xj_parser P; P.p = s.data; P.end = s.data + s.len; P.err = 0;
    struct xc_json_node* v = xj_parse_value(&P);
    xj_skip_ws(&P);
    if (P.err) { v->kind = XJ_ERROR; }
    return v;
}
