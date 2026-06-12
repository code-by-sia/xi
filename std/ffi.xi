// std/ffi — helpers for porting C libraries to Xi via `extern "C"`.
//
// An `extern "C" { ... }` block can carry build directives so a library
// declares its headers and how it links:
//
//   extern "C" {
//       include "<sqlite3.h>"     // -> #include <sqlite3.h>
//       link    "sqlite3"         // -> -lsqlite3
//       pkg     "sqlite3"         // -> pkg-config --cflags --libs sqlite3
//       cflags  "-I/opt/include"  // raw compile flags
//       ldflags "-L/opt/lib"      // raw link flags
//
//       producer sqlite3_open(path: cstring, ppDb: &mut Ptr) -> Integer
//       producer sqlite3_close(db: Ptr) -> Integer
//   }
//
// FFI primitives:
//   Ptr        — an opaque C pointer (`void*`); holds handles like `sqlite3*`.
//   cstring    — a C string (`const char*`).
//   &mut x     — the address of a variable (`&x`), for C out-parameters.
//   empty Ptr  — a null pointer.
//
// Use the bridges below to move text across the boundary, since a Xi `String`
// is not a `const char*`.

extern "C" {
    mapper xstd_cstr(s: String) -> cstring
    mapper xstd_from_cstr(p: cstring) -> String
}

// String -> cstring (NUL-terminated). Pass Xi text to a C function.
mapper toCString(s: String) -> cstring => xstd_cstr(s)

// cstring -> String. Bring a C result back into Xi.
mapper fromCString(p: cstring) -> String => xstd_from_cstr(p)
