// Porting a C library to Xi with `extern "C"`: a tiny SQLite binding.
//
// The `extern "C"` block declares the C functions (their signatures ARE the
// declarations — no header needed) and a `link` directive tells xc to link
// libsqlite3. Opaque handles (sqlite3*, sqlite3_stmt*) are held as `Ptr`
// (void*); C out-parameters are passed with `&mut`; `empty Ptr` is NULL.
//
//   xc examples/sqlite_demo.xi && ./build/sqlite_demo
//
// (Needs libsqlite3 — preinstalled on macOS; `apt-get install libsqlite3-dev`
//  or `brew install sqlite` elsewhere.)
import "std/log.xi"
import "std/ffi.xi"

extern "C" {
    link "sqlite3"

    producer sqlite3_libversion() -> cstring
    producer sqlite3_open(path: cstring, ppDb: &mut Ptr) -> Integer
    producer sqlite3_exec(db: Ptr, sql: cstring, cb: Ptr, arg: Ptr, errmsg: Ptr) -> Integer
    producer sqlite3_prepare_v2(db: Ptr, sql: cstring, nbyte: Integer, ppStmt: &mut Ptr, tail: Ptr) -> Integer
    producer sqlite3_step(stmt: Ptr) -> Integer
    producer sqlite3_column_int(stmt: Ptr, col: Integer) -> Integer
    producer sqlite3_column_text(stmt: Ptr, col: Integer) -> cstring
    producer sqlite3_finalize(stmt: Ptr) -> Integer
    producer sqlite3_close(db: Ptr) -> Integer
}

// SQLite result codes we care about
mapper SQLITE_ROW() -> Integer => 100

async entry (logger: Logger) main(args: String[]) {
    logger.info("SQLite " + fromCString(sqlite3_libversion()))

    let db = empty Ptr
    sqlite3_open(toCString(":memory:"), &mut db)

    sqlite3_exec(db, toCString("CREATE TABLE people(id INTEGER, name TEXT)"),
                 empty Ptr, empty Ptr, empty Ptr)
    sqlite3_exec(db, toCString("INSERT INTO people VALUES (1,'John Doe'),(2,'Linus'),(3,'Grace')"),
                 empty Ptr, empty Ptr, empty Ptr)

    let stmt = empty Ptr
    sqlite3_prepare_v2(db, toCString("SELECT id, name FROM people ORDER BY id"),
                       -1, &mut stmt, empty Ptr)

    let running = true
    while running {
        if sqlite3_step(stmt) == SQLITE_ROW() {
            let id   = sqlite3_column_int(stmt, 0)
            let name = fromCString(sqlite3_column_text(stmt, 1))
            logger.info("  #" + id + " " + name)
        } else {
            running = false
        }
    }

    sqlite3_finalize(stmt)
    sqlite3_close(db)
}

module App {}
