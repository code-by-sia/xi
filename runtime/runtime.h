/*
 * runtime.h — X language runtime support library
 *
 * Included by every generated C file.  Defines the primitive types,
 * string/array helpers, optional-type macros, and panic machinery.
 */
#ifndef XC_RUNTIME_H
#define XC_RUNTIME_H

/*
 * Expose POSIX/Darwin APIs (clock_gettime, CLOCK_MONOTONIC, struct timespec,
 * nanosleep, strdup, ...) even under -std=c99. On glibc these are hidden unless
 * a feature-test macro is set; macOS needs _DARWIN_C_SOURCE for the same.
 * These MUST be defined before any system header is included — and runtime.h is
 * the first include in every generated C file as well as runtime.c.
 */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE 1
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE 1
#endif

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <ctype.h>
#include <setjmp.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ─── Primitive type aliases ─────────────────────────────────────────────── */

typedef double          xc_number_t;
typedef int64_t         xc_integer_t;
typedef bool            xc_bool_t;
typedef uint32_t        xc_char_t;      /* Unicode scalar value (UTF-32)    */
typedef int64_t         xc_timestamp_t; /* nanoseconds since program start  */
typedef size_t          xc_size_t;

/* ─── String type ────────────────────────────────────────────────────────── */

typedef struct {
    const char* data;   /* UTF-8, NOT guaranteed NUL-terminated              */
    xc_size_t   len;    /* byte length                                        */
} xc_string_t;

static inline xc_string_t xc_string_from_cstr(const char* s) {
    return (xc_string_t){ .data = s, .len = s ? strlen(s) : 0 };
}

static inline xc_string_t xc_string_from_buf(const char* data, xc_size_t len) {
    return (xc_string_t){ .data = data, .len = len };
}

/* Allocate a NUL-terminated copy (for passing to C APIs) */
static inline char* xc_string_to_cstr(xc_string_t s) {
    char* buf = (char*)malloc(s.len + 1);
    if (!buf) abort();
    memcpy(buf, s.data, s.len);
    buf[s.len] = '\0';
    return buf;
}

static inline xc_bool_t xc_string_eq(xc_string_t a, xc_string_t b) {
    return a.len == b.len && memcmp(a.data, b.data, a.len) == 0;
}

/* Concatenate two strings — result is heap-allocated */
static inline xc_string_t xc_string_concat(xc_string_t a, xc_string_t b) {
    xc_size_t len = a.len + b.len;
    char* buf = (char*)malloc(len + 1);
    if (!buf) abort();
    memcpy(buf, a.data, a.len);
    memcpy(buf + a.len, b.data, b.len);
    buf[len] = '\0';
    return (xc_string_t){ .data = buf, .len = len };
}

/* ─── Bytes type ─────────────────────────────────────────────────────────── */
/* A buffer of raw bytes. Like xc_string_t it is a {data,len} fat pointer passed
   by value; copies share the buffer and it is never mutated in place, so value
   semantics hold. Functions that produce new bytes heap-allocate. */
typedef struct {
    const unsigned char* data;
    xc_size_t            len;
} xc_bytes_t;

static inline xc_integer_t bytes_len(xc_bytes_t b) { return (xc_integer_t)b.len; }

static inline xc_integer_t bytes_get(xc_bytes_t b, xc_integer_t i) {
    if (i < 0 || (xc_size_t)i >= b.len) return -1;
    return (xc_integer_t)b.data[(xc_size_t)i];
}

static inline xc_bytes_t bytes_empty(void) {
    return (xc_bytes_t){ .data = NULL, .len = 0 };
}

static inline xc_bytes_t bytes_slice(xc_bytes_t b, xc_integer_t from, xc_integer_t to) {
    if (from < 0) from = 0;
    if ((xc_size_t)to > b.len) to = (xc_integer_t)b.len;
    if (from >= to) return bytes_empty();
    return (xc_bytes_t){ .data = b.data + from, .len = (xc_size_t)(to - from) };
}

static inline xc_bytes_t bytes_concat(xc_bytes_t a, xc_bytes_t b) {
    xc_size_t len = a.len + b.len;
    unsigned char* buf = (unsigned char*)malloc(len ? len : 1);
    if (!buf) abort();
    if (a.len) memcpy(buf, a.data, a.len);
    if (b.len) memcpy(buf + a.len, b.data, b.len);
    return (xc_bytes_t){ .data = buf, .len = len };
}

/* Copy a string's bytes into a fresh Bytes buffer (and vice versa). */
static inline xc_bytes_t bytes_from_string(xc_string_t s) {
    unsigned char* buf = (unsigned char*)malloc(s.len ? s.len : 1);
    if (!buf) abort();
    if (s.len) memcpy(buf, s.data, s.len);
    return (xc_bytes_t){ .data = buf, .len = s.len };
}

static inline xc_string_t bytes_to_string(xc_bytes_t b) {
    char* buf = (char*)malloc(b.len + 1);
    if (!buf) abort();
    if (b.len) memcpy(buf, b.data, b.len);
    buf[b.len] = '\0';
    return (xc_string_t){ .data = buf, .len = b.len };
}

/* Bytes is a runtime primitive, so its Result/optional/array shapes live here
   (the compiler emits these only for the built-in scalars and user types). */
typedef struct { bool ok; xc_bytes_t value; xc_string_t err; } xc_res_bytes_t;
typedef struct { bool has_value; xc_bytes_t value; }           xc_opt_bytes_t;
typedef struct { xc_bytes_t* data; xc_size_t len; xc_size_t cap; } xc_arr_bytes_t;

/* JSON value — an opaque, heap-allocated DOM node used by std/json (the
   serialization library). It is referenced from X as the `Json` type; the
   struct itself is private to runtime.c. */
typedef struct xc_json_node* xc_Json_t;

/* Event system (std/events). An event is a type-erased envelope: a topic, the
   payload's type name, and an opaque pointer to a heap copy of the typed value.
   The default transport moves envelopes through an in-memory FIFO with no
   serialization; external transports (de)serialize the payload themselves. */
typedef struct xc_event_env* xc_Event_t;

/* Web (std/web): an HTTP request/response and a tiny HTTP/1.1 server. The
   generated router is registered via xstd_web_set_dispatch and run by serve. */
typedef struct xc_web_request*  xc_Request_t;
typedef struct xc_web_response* xc_Response_t;
xc_string_t   xstd_req_method(xc_Request_t);
xc_string_t   xstd_req_path(xc_Request_t);
xc_string_t   xstd_req_query(xc_Request_t, xc_string_t name);
xc_string_t   xstd_req_header(xc_Request_t, xc_string_t name);
xc_string_t   xstd_req_param(xc_Request_t, xc_string_t name);
xc_string_t   xstd_req_body(xc_Request_t);
xc_Response_t xstd_resp(xc_integer_t status, xc_string_t body, xc_string_t ctype);
xc_bool_t     xstd_web_match(xc_Request_t, xc_string_t method, xc_string_t pattern);
void          xstd_web_set_dispatch(xc_Response_t (*fn)(xc_Request_t));
void          xstd_web_serve(xc_integer_t port);

/* Handler-interface model (std/web v2): the request and a *mutable* response are
   handed to a WebRequestHandler.handle(req,res); the handler fills the response
   via xstd_resp_set. The generated dispatch is registered via xstd_web_set_handler. */
typedef struct xc_web_request*  xc_HttpRequest_t;
typedef struct xc_web_response* xc_HttpResponse_t;
void          xstd_resp_set(xc_HttpResponse_t, xc_integer_t status, xc_string_t body, xc_string_t ctype);
xc_integer_t  xstd_resp_status(xc_HttpResponse_t);
void          xstd_web_set_handler(void (*fn)(xc_HttpRequest_t, xc_HttpResponse_t));
void          xstd_web_serve_tls(xc_integer_t port, xc_string_t certPath, xc_string_t keyPath);
xc_string_t   xstd_https_fetch(xc_string_t host, xc_integer_t port, xc_string_t request);
void          xstd_web_serve_http2(xc_integer_t port, xc_string_t certPath, xc_string_t keyPath);

/* Threading (std/thread): share-nothing OS threads communicating over
   thread-safe channels. A `parallel { }` block lifts to a thread function and is
   started via xstd_thread_spawn, returning a Thread handle (stop/wait/running).
   Channels carry copied string payloads (the only thing crossing the boundary). */
typedef struct xc_chan*   xc_Channel_t;
typedef struct xc_thread* xc_Thread_t;
xc_Channel_t  xstd_chan_new(void);
void          xstd_chan_send(xc_Channel_t, xc_string_t);
xc_string_t   xstd_chan_recv(xc_Channel_t);
void          xstd_chan_close(xc_Channel_t);
xc_Thread_t   xstd_thread_spawn(void* (*fn)(void*), void* arg);
void          xstd_thread_stop(xc_Thread_t);
void          xstd_thread_wait(xc_Thread_t);
xc_bool_t     xstd_thread_running(xc_Thread_t);
xc_bool_t     xstd_thread_stopped(void);

xc_Event_t   xstd_event_make(xc_string_t topic, xc_string_t type, void* payload);
xc_string_t  xstd_event_topic(xc_Event_t);
xc_string_t  xstd_event_type(xc_Event_t);
void*        xstd_event_payload(xc_Event_t);
void         xstd_eventq_push(xc_Event_t);
xc_integer_t xstd_eventq_len(void);
xc_Event_t   xstd_eventq_shift(void);
xc_Event_t   xstd_eventq_pop_blocking(void);
void         xstd_eventq_close(void);

/* Number → string */
static inline xc_string_t xc_number_to_string(xc_number_t n) {
    char buf[64];
    if (n == (xc_integer_t)n)
        snprintf(buf, sizeof(buf), "%lld", (long long)(xc_integer_t)n);
    else
        snprintf(buf, sizeof(buf), "%g", n);
    return xc_string_from_cstr(strdup(buf));
}

static inline xc_string_t xc_integer_to_string(xc_integer_t n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return xc_string_from_cstr(strdup(buf));
}

static inline xc_string_t xc_bool_to_string(xc_bool_t b) {
    return xc_string_from_cstr(b ? "true" : "false");
}

/* Simple regex match using libc (only ^ $ . * + ? supported) */
xc_bool_t xc_string_matches(xc_string_t s, const char* pattern);

/* ─── Array type ─────────────────────────────────────────────────────────── */

typedef struct {
    xc_string_t* data;
    xc_size_t    len;
    xc_size_t    cap;
} xc_arr_string_t;

/* Arrays of primitives — so they can be struct/event fields and array literals. */
typedef struct { xc_integer_t* data; xc_size_t len; xc_size_t cap; } xc_arr_integer_t;
typedef struct { xc_number_t*  data; xc_size_t len; xc_size_t cap; } xc_arr_number_t;
typedef struct { xc_bool_t*    data; xc_size_t len; xc_size_t cap; } xc_arr_bool_t;
typedef struct { xc_char_t*    data; xc_size_t len; xc_size_t cap; } xc_arr_char_t;

typedef struct {
    void*      data;
    xc_size_t  len;
    xc_size_t  cap;
} xc_arr_any_t;

/* ─── Optional helpers ───────────────────────────────────────────────────── */

typedef struct { bool has_value; xc_number_t  value; } xc_opt_number_t;
typedef struct { bool has_value; xc_integer_t value; } xc_opt_integer_t;
typedef struct { bool has_value; xc_bool_t    value; } xc_opt_bool_t;
typedef struct { bool has_value; xc_string_t  value; } xc_opt_string_t;
typedef struct { bool has_value; xc_char_t    value; } xc_opt_char_t;
typedef struct { bool has_value; xc_size_t    value; } xc_opt_size_t;

#define XC_SOME(val)  { .has_value = true,  .value = (val) }
#define XC_NONE_VAL   { .has_value = false }

/* ─── Constraint checking ────────────────────────────────────────────────── */

#define XC_CONSTRAINT_CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "xc: constraint violation: %s  (at %s:%d)\n", \
                    (msg), __FILE__, __LINE__); \
            abort(); \
        } \
    } while (0)

#define XC_PANIC(msg) \
    do { \
        fprintf(stderr, "xc: panic: %s  (at %s:%d)\n", (msg), __FILE__, __LINE__); \
        abort(); \
    } while (0)

/* ─── System I/O ─────────────────────────────────────────────────────────── */

static inline void xc_stdout_writeln(xc_string_t s) {
    fwrite(s.data, 1, s.len, stdout);
    fputc('\n', stdout);
}

static inline void xc_stdout_write(xc_string_t s) {
    fwrite(s.data, 1, s.len, stdout);
}

static inline void xc_stderr_writeln(xc_string_t s) {
    fwrite(s.data, 1, s.len, stderr);
    fputc('\n', stderr);
}

static inline xc_opt_string_t xc_stdin_readline(void) {
    char buf[4096];
    if (!fgets(buf, sizeof(buf), stdin))
        return (xc_opt_string_t){ .has_value = false };
    xc_size_t len = strlen(buf);
    if (len > 0 && buf[len-1] == '\n') buf[--len] = '\0';
    char* copy = (char*)malloc(len + 1);
    memcpy(copy, buf, len + 1);
    return (xc_opt_string_t){ .has_value = true,
                               .value = { .data = copy, .len = len } };
}

/* ─── Math helpers ───────────────────────────────────────────────────────── */

static inline xc_number_t  xc_math_sqrt(xc_number_t x)  { return sqrt(x);  }
static inline xc_number_t  xc_math_pow(xc_number_t x, xc_number_t y) { return pow(x,y); }
static inline xc_number_t  xc_math_abs_n(xc_number_t x) { return fabs(x);  }
static inline xc_integer_t xc_math_abs_i(xc_integer_t x){ return x < 0 ? -x : x; }
static inline xc_number_t  xc_math_floor(xc_number_t x) { return floor(x); }
static inline xc_number_t  xc_math_ceil(xc_number_t x)  { return ceil(x);  }
static inline xc_number_t  xc_math_round(xc_number_t x) { return round(x); }

/* ─── Timestamp ──────────────────────────────────────────────────────────── */

static inline xc_timestamp_t xc_time_now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (xc_timestamp_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

/* ─── Bootstrap helpers (used by xc-in-X compiler) ──────────────────────── */

/* Character at position i in string (0-terminated if out of range). */
static inline xc_integer_t string_char_at(xc_string_t s, xc_integer_t i) {
    return (i >= 0 && (xc_size_t)i < s.len)
        ? (xc_integer_t)(unsigned char)s.data[(xc_size_t)i]
        : 0;
}
static inline xc_integer_t string_len(xc_string_t s) { return (xc_integer_t)s.len; }

/* Slice [from, to) — returned string borrows from the original. */
static inline xc_string_t string_slice(xc_string_t s, xc_integer_t from, xc_integer_t to) {
    if (from < 0) from = 0;
    if ((xc_size_t)to  > s.len) to = (xc_integer_t)s.len;
    if (from >= to) return (xc_string_t){ .data = s.data, .len = 0 };
    return (xc_string_t){ .data = s.data + from, .len = (xc_size_t)(to - from) };
}

/* Character class helpers */
static inline xc_bool_t is_alpha(xc_integer_t c)  { return isalpha((int)c) != 0; }
static inline xc_bool_t is_digit(xc_integer_t c)  { return isdigit((int)c) != 0; }
static inline xc_bool_t is_alnum(xc_integer_t c)  { return isalnum((int)c) != 0; }
static inline xc_bool_t is_space_c(xc_integer_t c){ return isspace((int)c) != 0; }

/* Integer → string conversion (heap-allocated) */
static inline xc_string_t int_to_string(xc_integer_t n) { return xc_integer_to_string(n); }
static inline xc_string_t number_to_str(xc_number_t  n) { return xc_number_to_string(n);  }

/* File I/O */
xc_string_t file_read_all(xc_string_t path);

/* Diagnostics: set the current source file, then report an error at a line and
   exit(1) with `xc: <file>:<line>: error: <msg>`. */
void diag_set_file(xc_string_t path);
void diag_error(xc_integer_t line, xc_string_t msg);

/* ─── Interrupts (resumable conditions) ──────────────────────────────────────
   A dynamic stack of handlers. `try` pushes one and setjmp()s the skip target;
   `signal` finds the nearest matching handler, calls it (stack intact) for a
   resolution (1=recover, 0=skip), then continues or longjmp()s. */
typedef int (*xc_int_fn)(void* payload);
typedef struct xc_handler {
    int                type_id;
    xc_int_fn          fn;
    jmp_buf            unwind;
    struct xc_handler* prev;
} xc_handler_t;
extern xc_handler_t* xc_handlers;
xc_handler_t* xc_int_find(int type_id);
void          xc_int_unhandled(const char* name);
/* REPL / tooling */
xc_string_t  read_line(void);
xc_bool_t    stdin_eof(void);
void         flush_out(void);
xc_integer_t run_command(xc_string_t cmd);
xc_string_t  get_env(xc_string_t name, xc_string_t dflt);

/* Standard library primitives (wrapped by std/*.x) */
xc_number_t  xstd_sqrt(xc_number_t);  xc_number_t xstd_pow(xc_number_t, xc_number_t);
xc_number_t  xstd_exp(xc_number_t);   xc_number_t xstd_ln(xc_number_t);
xc_number_t  xstd_log10(xc_number_t); xc_number_t xstd_sin(xc_number_t);
xc_number_t  xstd_cos(xc_number_t);   xc_number_t xstd_tan(xc_number_t);
xc_number_t  xstd_floor(xc_number_t); xc_number_t xstd_ceil(xc_number_t);
xc_number_t  xstd_round(xc_number_t); xc_number_t xstd_fabs(xc_number_t);
xc_number_t  xstd_pi(void);           xc_number_t xstd_e(void);
xc_integer_t xstd_strlen(xc_string_t);
xc_integer_t xstd_char_at(xc_string_t, xc_integer_t);
xc_string_t  xstd_substring(xc_string_t, xc_integer_t, xc_integer_t);
xc_string_t  xstd_trim(xc_string_t);
xc_bool_t    xstd_starts_with(xc_string_t, xc_string_t);
xc_bool_t    xstd_ends_with(xc_string_t, xc_string_t);
xc_integer_t xstd_index_of(xc_string_t, xc_string_t);
xc_bool_t    xstd_contains(xc_string_t, xc_string_t);
xc_string_t  xstd_to_upper(xc_string_t);
xc_string_t  xstd_to_lower(xc_string_t);
xc_string_t  xstd_repeat(xc_string_t, xc_integer_t);
xc_string_t  xstd_replace(xc_string_t, xc_string_t, xc_string_t);
xc_arr_string_t xstd_split(xc_string_t s, xc_string_t sep);
xc_string_t  xstd_join(xc_arr_string_t parts, xc_string_t sep);
xc_bool_t    xstd_num_ok(xc_string_t);  xc_number_t  xstd_to_number(xc_string_t);
xc_bool_t    xstd_int_ok(xc_string_t);  xc_integer_t xstd_to_integer(xc_string_t);
xc_bool_t    xstd_file_exists(xc_string_t);
/* filesystem */
xc_bytes_t   xstd_read_bytes(xc_string_t path);
xc_bool_t    xstd_write_bytes(xc_string_t path, xc_bytes_t b);
xc_bool_t    xstd_is_dir(xc_string_t path);
xc_bool_t    xstd_is_file(xc_string_t path);
xc_integer_t xstd_file_size(xc_string_t path);
xc_integer_t xstd_mtime(xc_string_t path);
xc_bool_t    xstd_remove(xc_string_t path);
xc_bool_t    xstd_rename(xc_string_t from, xc_string_t to);
xc_bool_t    xstd_mkdir(xc_string_t path);
xc_bool_t    xstd_mkdir_all(xc_string_t path);
xc_string_t  xstd_cwd(void);
xc_arr_string_t xstd_list_dir(xc_string_t path);
/* networking (TCP, blocking) */
xc_integer_t xstd_tcp_connect(xc_string_t host, xc_integer_t port);
xc_integer_t xstd_tcp_listen(xc_integer_t port, xc_integer_t backlog);
xc_integer_t xstd_tcp_accept(xc_integer_t fd);
xc_integer_t xstd_sock_port(xc_integer_t fd);
xc_integer_t xstd_sock_send(xc_integer_t fd, xc_bytes_t data);
xc_bytes_t   xstd_sock_recv(xc_integer_t fd, xc_integer_t max);
xc_bool_t    xstd_sock_close(xc_integer_t fd);
void         xstd_exit(xc_integer_t);
xc_integer_t xstd_now_nanos(void);
void         xstd_sleep_ms(xc_integer_t);
xc_bool_t   file_write(xc_string_t path, xc_string_t content);
xc_bool_t   file_writeln(xc_string_t path, xc_string_t line);  /* appends newline */

/* Array helpers for bootstrap compiler (typed push) */
typedef struct { xc_string_t* data; xc_size_t len; xc_size_t cap; } xc_arr_string_heap_t;

/* ─── Array literal helpers ──────────────────────────────────────────────── */

/* Build an array fat pointer from a literal element list.
 * Usage:  XC_ARRAY_LIT(xc_Player_t, elem1, elem2, elem3)             */
#define XC_ARRAY_LIT(ElemType, ...) \
    ((struct { ElemType* data; xc_size_t len; xc_size_t cap; }){ \
        .data = (ElemType[]){ __VA_ARGS__ }, \
        .len  = sizeof((ElemType[]){ __VA_ARGS__ }) / sizeof(ElemType), \
        .cap  = sizeof((ElemType[]){ __VA_ARGS__ }) / sizeof(ElemType) \
    })

/* Empty typed array. */
#define XC_ARRAY_EMPTY(ElemType) \
    ((struct { ElemType* data; xc_size_t len; xc_size_t cap; }){ \
        .data = NULL, .len = 0, .cap = 0 \
    })

/* ─── Optional helpers ───────────────────────────────────────────────────── */

/* String-aware + operator: both sides must already be xc_string_t.
 * The X compiler emits explicit xc_number_to_string / xc_integer_to_string
 * wrapping when it knows one operand is not a string.               */
#define xc_string_add(a, b) xc_string_concat((a), (b))

/* ─── Process ────────────────────────────────────────────────────────────── */

static inline void xc_process_exit(xc_integer_t code) {
    exit((int)code);
}

#ifdef __cplusplus
}
#endif

#endif /* XC_RUNTIME_H */
