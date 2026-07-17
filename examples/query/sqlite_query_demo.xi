// xi-query against a real SQLite database.
//
// A QueryProvider is the whole integration surface: implement one method,
// run(plan), and every xi-query chain works against your backend. Here the
// provider renders the reified plan to SQL with std/sql's SqliteDialect,
// executes it through the libsqlite3 FFI with bound parameters (never spliced),
// and returns rows as Json — which `collect` decodes back into typed values.
//
//   xc examples/query/sqlite_query_demo.xi && ./build/sqlite_query_demo
//
// (Needs libsqlite3 — preinstalled on macOS; `apt-get install libsqlite3-dev`
//  or `brew install sqlite` elsewhere.)
import "std/query.xi"
import "std/sql.xi"
import "std/json.xi"
import "std/ffi.xi"
import "std/log.xi"

extern "C" {
    link "sqlite3"

    producer sqlite3_open(path: cstring, ppDb: &mut Ptr) -> Integer
    producer sqlite3_exec(db: Ptr, sql: cstring, cb: Ptr, arg: Ptr, err: Ptr) -> Integer
    producer sqlite3_prepare_v2(db: Ptr, sql: cstring, n: Integer, ppStmt: &mut Ptr, tail: Ptr) -> Integer
    producer sqlite3_bind_double(stmt: Ptr, idx: Integer, val: Number) -> Integer
    producer sqlite3_bind_text(stmt: Ptr, idx: Integer, val: cstring, n: Integer, dtor: Ptr) -> Integer
    producer sqlite3_step(stmt: Ptr) -> Integer
    producer sqlite3_column_count(stmt: Ptr) -> Integer
    producer sqlite3_column_name(stmt: Ptr, col: Integer) -> cstring
    producer sqlite3_column_type(stmt: Ptr, col: Integer) -> Integer
    producer sqlite3_column_double(stmt: Ptr, col: Integer) -> Number
    producer sqlite3_column_text(stmt: Ptr, col: Integer) -> cstring
    producer sqlite3_finalize(stmt: Ptr) -> Integer
}

// SQLite constants we need: the row step code and the column type tags.
mapper SQLITE_ROW()  -> Integer => 100
mapper COL_TEXT()    -> Integer => 3

type User = { id: Integer, name: String, age: Integer, active: Bool }

// Setup surface, kept off the QueryProvider contract (like MemorySource's
// RowStore): open the connection and run schema/seed statements.
interface Db {
    consumer open(path: String)
    consumer exec(sql: String)
}

// The provider — one class, two views, both bound to the same singleton.
class SqliteProvider implements QueryProvider, Db {
    deps {}
    state { db: Ptr = empty Ptr }
    mapper name() -> String => "sqlite"

    consumer open(path: String) {
        let d = empty Ptr
        sqlite3_open(toCString(path), &mut d)
        this.db = d
    }
    consumer exec(sql: String) {
        sqlite3_exec(this.db, toCString(sql), empty Ptr, empty Ptr, empty Ptr)
    }

    // Render the plan, bind its params, execute, and hand the rows back as
    // Json — exactly what `collect` expects. This is the entire binding.
    producer run(plan: QueryPlan) -> Json {
        let r = sqlRender(plan, SqliteDialect {} as SqlDialect)
        if not r.ok { return json.array() }
        let stmt = r.value

        let ps = empty Ptr
        sqlite3_prepare_v2(this.db, toCString(stmt.text), 0 - 1, &mut ps, empty Ptr)

        // bind captured values positionally — a String binds as text, anything
        // numeric as a double (SQLITE_STATIC: toCString buffers outlive the step)
        let np = json.length(stmt.params)
        let i = 0
        while i < np {
            let v = json.at(stmt.params, i)
            if json.isString(v) {
                sqlite3_bind_text(ps, i + 1, toCString(json.asString(v)), 0 - 1, empty Ptr)
            } else {
                sqlite3_bind_double(ps, i + 1, json.asNumber(v))
            }
            i = i + 1
        }

        // read every row into a Json object keyed by column name
        let rows = json.array()
        let going = true
        while going {
            if sqlite3_step(ps) == SQLITE_ROW() {
                let ncols = sqlite3_column_count(ps)
                let row = json.object()
                let c = 0
                while c < ncols {
                    let cname = fromCString(sqlite3_column_name(ps, c))
                    if sqlite3_column_type(ps, c) == COL_TEXT() {
                        row = json.set(row, cname, json.str(fromCString(sqlite3_column_text(ps, c))))
                    } else {
                        row = json.set(row, cname, json.num(sqlite3_column_double(ps, c)))
                    }
                    c = c + 1
                }
                rows = json.push(rows, row)
            } else {
                going = false
            }
        }
        sqlite3_finalize(ps)
        return rows
    }

    // Write side: bind each JSON value positionally, same rules as run().
    consumer bindOne(ps: Ptr, slot: Integer, v: Json) {
        if json.isString(v) {
            sqlite3_bind_text(ps, slot, toCString(json.asString(v)), 0 - 1, empty Ptr)
        } else {
            sqlite3_bind_double(ps, slot, json.asNumber(v))
        }
    }

    // Upsert one row: columns come straight from the JSON object's keys.
    consumer insert(source: String, row: Json) {
        let nk = json.length(row)
        let cols = ""
        let ph = ""
        let i = 0
        while i < nk {
            if i > 0 { cols = cols + ", "  ph = ph + ", " }
            cols = cols + "\"" + json.keyAt(row, i) + "\""
            ph = ph + "?"
            i = i + 1
        }
        let sql = "INSERT INTO " + source + " (" + cols + ") VALUES (" + ph + ")"
        let ps = empty Ptr
        sqlite3_prepare_v2(this.db, toCString(sql), 0 - 1, &mut ps, empty Ptr)
        let j = 0
        while j < nk {
            bindOne(ps, j + 1, json.get(row, json.keyAt(row, j)))
            j = j + 1
        }
        sqlite3_step(ps)
        sqlite3_finalize(ps)
    }

    // Delete rows whose key column equals id.
    consumer remove(source: String, key: String, id: Json) {
        let sql = "DELETE FROM " + source + " WHERE \"" + key + "\" = ?"
        let ps = empty Ptr
        sqlite3_prepare_v2(this.db, toCString(sql), 0 - 1, &mut ps, empty Ptr)
        bindOne(ps, 1, id)
        sqlite3_step(ps)
        sqlite3_finalize(ps)
    }
}

module App {
    bind QueryProvider -> SqliteProvider as singleton
    bind Db            -> SqliteProvider as singleton
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    // 1. open + seed a database (schema mirrors the User type's fields)
    let db = App.resolve(Db)
    db.open(":memory:")
    db.exec("CREATE TABLE users(id INTEGER, name TEXT, age INTEGER, active INTEGER)")
    db.exec("INSERT INTO users VALUES (1,'Cara',44,1),(2,'Abe',15,1),(3,'Bea',30,0),(4,'Dan',51,1)")

    let minAge = 18

    // 2. the query — the SQL it becomes is visible for illustration
    let plan = query.from<User>("users")
        .filter { it.age >= minAge and it.name.contains("a") }
        .sortedBy { it.name }
        .take(5)
        .plan
    let rendered = (sqlRender(plan, SqliteDialect {} as SqlDialect)).value
    logger.info("SQL:    " + rendered.text)
    logger.info("params: " + json.stringify(rendered.params))

    // 3. run it through the provider — comes back as List<User>, no casts
    let adults = query.from<User>("users")
        .filter { it.age >= minAge and it.name.contains("a") }
        .sortedBy { it.name }
        .take(5)
        .collect(App.resolve(QueryProvider))

    logger.info("rows:   " + adults.len())
    for u in adults { logger.info("  #" + u.id + " " + u.name + " (" + u.age + ")") }
    return 0
}
