# C interop & porting libraries (`extern "C"`)

Xi compiles to C, so binding a C library is direct: declare its functions in an
`extern "C"` block, tell `xc` how to link it, and call them. This is how you
port a C library — SQLite, zlib, libcurl, your own `.c` — into Xi.

## An `extern "C"` block

```x
extern "C" {
    link "sqlite3"                                       // build directive

    producer sqlite3_open(path: cstring, ppDb: &mut Ptr) -> Integer
    producer sqlite3_close(db: Ptr) -> Integer
    producer sqlite3_libversion() -> cstring
}
```

Each `kind name(params) -> ret` line declares one C function — the declaration
*is* the binding. Pick any function kind (`producer`/`mapper`/…); for FFI it only
affects intent, not codegen. The signatures generate matching C `extern`
declarations, and the linker resolves the symbols from the library you name.

## Build directives

Inside an `extern "C"` block you can declare how the library is found and linked.
They apply to the whole program (gather as many as you need, across files):

| Directive | Emits | Use |
|-----------|-------|-----|
| `link "name"` | `-lname` | link a library (`link "sqlite3"` → `-lsqlite3`) |
| `pkg "name"` | `pkg-config --cflags --libs name` | link via pkg-config (portable include + lib paths) |
| `cflags "…"` | the flags verbatim | extra compile flags, e.g. `cflags "-I/opt/include"` |
| `ldflags "…"` | the flags verbatim | extra link flags, e.g. `ldflags "-L/opt/lib"` |
| `include "<h.h>"` | `#include <h.h>` | pull in a C header (for macros/types you reference) |

`include "name.h"` (no brackets) emits `#include <name.h>`; pass `include
"\"name.h\""` for a local `#include "name.h"`.

`pkg` is the most portable for real libraries:

```x
extern "C" {
    pkg "libcurl"
    producer curl_easy_init() -> Ptr
    producer curl_easy_cleanup(h: Ptr) -> Void
}
```

## FFI types

| Xi | C | Notes |
|----|---|-------|
| `Ptr` | `void*` | opaque handle — `sqlite3*`, `FILE*`, `sqlite3_stmt*` |
| `cstring` | `const char*` | a C string |
| `&mut x` | `&x` | address of a variable — for C **out-parameters** |
| `empty Ptr` | `(void*)0` | a null pointer |
| `Integer`/`Number`/`Bool`/`Size` | `long long`/`double`/`bool`/`size_t` | scalars pass through |

A Xi `String` is **not** a `const char*`, so bridge across the boundary with
`std/ffi`:

```x
import "std/ffi.xi"

toCString(s: String) -> cstring     // Xi String  -> C string
fromCString(p: cstring) -> String   // C string   -> Xi String
```

> Declare externs **or** `include` the header for a given function — not both
> with mismatched signatures, or C will report conflicting declarations. For a
> simple port, declaring the externs and linking (no header) is cleanest; reach
> for `include` only when you need the header's types or macros.

## Worked example: a SQLite binding

```x
import "std/log.xi"
import "std/ffi.xi"

extern "C" {
    link "sqlite3"

    producer sqlite3_open(path: cstring, ppDb: &mut Ptr) -> Integer
    producer sqlite3_exec(db: Ptr, sql: cstring, cb: Ptr, arg: Ptr, errmsg: Ptr) -> Integer
    producer sqlite3_prepare_v2(db: Ptr, sql: cstring, n: Integer, ppStmt: &mut Ptr, tail: Ptr) -> Integer
    producer sqlite3_step(stmt: Ptr) -> Integer
    producer sqlite3_column_int(stmt: Ptr, col: Integer) -> Integer
    producer sqlite3_column_text(stmt: Ptr, col: Integer) -> cstring
    producer sqlite3_finalize(stmt: Ptr) -> Integer
    producer sqlite3_close(db: Ptr) -> Integer
}

mapper SQLITE_ROW() -> Integer => 100

async entry (logger: Logger) main(args: String[]) {
    let db = empty Ptr
    sqlite3_open(toCString(":memory:"), &mut db)        // out-param via &mut

    sqlite3_exec(db, toCString("CREATE TABLE people(id INTEGER, name TEXT)"),
                 empty Ptr, empty Ptr, empty Ptr)        // NULLs for callback/errmsg
    sqlite3_exec(db, toCString("INSERT INTO people VALUES (1,'Ada'),(2,'Grace')"),
                 empty Ptr, empty Ptr, empty Ptr)

    let stmt = empty Ptr
    sqlite3_prepare_v2(db, toCString("SELECT id, name FROM people ORDER BY id"),
                       -1, &mut stmt, empty Ptr)

    let running = true
    while running {
        if sqlite3_step(stmt) == SQLITE_ROW() {
            let id   = sqlite3_column_int(stmt, 0)
            let name = fromCString(sqlite3_column_text(stmt, 1))
            logger.info("#" + id + " " + name)
        } else { running = false }
    }
    sqlite3_finalize(stmt)
    sqlite3_close(db)
}

module App {}
```

```console
$ xc sqlite_demo.xi && ./build/sqlite_demo
[info] #1 Ada
[info] #2 Grace
```

The full runnable version is [`examples/stdlib/sqlite_demo.xi`](https://github.com/code-by-sia/xi/blob/main/examples/stdlib/sqlite_demo.xi).

## Packaging a binding as a library

Put the `extern "C"` block and a set of Xi wrapper functions in their own `.xi`
file and `import` it — the build directives travel with it, so users of your
binding just `import "sqlite.xi"` and link is handled automatically:

```x title="sqlite.xi"
import "std/ffi.xi"
extern "C" { link "sqlite3"  /* …decls… */ }

// idiomatic Xi surface over the raw C calls
creator openDb(path: String) -> Ptr { let db = empty Ptr; sqlite3_open(toCString(path), &mut db); return db }
```

## How it works

`xc` emits the `#include`s and a `/* XC-BUILD-FLAGS: … */` marker into the
generated C; the compiler driver reads that marker and appends the flags (and
runs `pkg-config` for `pkg` entries) to the `cc` command. Linking is your system
`cc`, so any library your toolchain can link, Xi can bind.

> **Trust:** build directives place flags on the `cc` command line, so only
> compile `extern "C"` code you trust — the same caution as a `Makefile`.
