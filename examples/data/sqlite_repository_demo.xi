// A CrudRepository backed by real SQLite.
//
// The repository (std/data) is backend-agnostic: it speaks the QueryProvider
// contract — run(plan) for reads, insert / remove for writes. Bind that contract
// to the SqliteProvider below and the same UserRepo that runs in-memory in tests
// now persists to SQLite, with `findAll()` returning a composable Query.
import "std/data.xi"
import "std/query.xi"
import "std/sql.xi"
import "std/json.xi"
import "std/io.xi"
import "std/ffi.xi"

type User    = { id: Integer, name: String, age: Integer, pw: String }
type UserApi = { id: Integer, name: String, age: Integer }   // no pw on the wire

// ── libsqlite3 ────────────────────────────────────────────────────────
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
mapper SQLITE_ROW() -> Integer { return 100 }
mapper COL_TEXT()   -> Integer { return 3 }

// A second view on the provider, used only for schema setup.
interface Db {
    consumer open(path: String)
    consumer exec(sql: String)
}

// ── the provider: run / insert / remove over SQLite ───────────────────
class SqliteProvider implements QueryProvider, Db {
    deps {}
    state { db: Ptr = empty Ptr }

    consumer open(path: String) {
        let d = empty Ptr
        sqlite3_open(toCString(path), &mut d)
        this.db = d
    }
    consumer exec(sql: String) {
        sqlite3_exec(this.db, toCString(sql), empty Ptr, empty Ptr, empty Ptr)
    }

    // Render the plan, bind its params, run it, hand rows back as Json.
    producer run(plan: QueryPlan) -> Json {
        let r = sqlRender(plan, SqliteDialect {} as SqlDialect)
        if not r.ok { return json.array() }
        let stmt = r.value
        let ps = empty Ptr
        sqlite3_prepare_v2(this.db, toCString(stmt.text), 0 - 1, &mut ps, empty Ptr)
        let np = json.length(stmt.params)
        let i = 0
        while i < np {
            bindOne(ps, i + 1, json.at(stmt.params, i))
            i = i + 1
        }
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

// ── the repository: five methods, backend-agnostic ────────────────────
class UserRepo implements CrudRepository<Integer, User, UserApi> {
    deps { db: QueryProvider }
    state { source: String = "users" }

    producer findAll() -> Query<User> => query.from<User>(this.source)
    producer findById(id: Integer) -> User? {
        let rows = query.from<User>(this.source).filter { it.id == id }.take(1).toList()
        if rows.len() > 0 { return rows.get(0) }
        return none
    }
    consumer save(e: User)           { db.remove(this.source, "id", json.int(e.id))  db.insert(this.source, e as Json) }
    consumer delete(e: User)         { deleteById(e.id) }
    consumer deleteById(id: Integer) { db.remove(this.source, "id", json.int(id)) }
    // convertTo / convertFrom inherited from Repository as defaults
}

// A small driver: the repository is injected by its generic interface (a class's
// `deps` resolves generic bindings; UserRepo is the sole implementor).
interface DemoApp { action run() }

class Demo implements DemoApp {
    deps { repo: CrudRepository<Integer, User, UserApi>, schema: Db }

    action run() {
        schema.open(":memory:")
        schema.exec("CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, age INTEGER, pw TEXT)")

        // writes go through the repository
        repo.save(User { id: 1, name: "Cara", age: 44, pw: "s1" })
        repo.save(User { id: 2, name: "Abe",  age: 15, pw: "s2" })
        repo.save(User { id: 3, name: "Bea",  age: 30, pw: "s3" })

        // findAll() is a composable Query over the bound provider
        let adults = repo.findAll().filter { it.age >= 18 }.sortedBy { it.name }.toList()
        io.println("adults: " + adults.len())
        for u in adults { io.println("  #" + u.id + " " + u.name + " (" + u.age + ")") }

        // findById returns an optional; convertTo drops pw for the wire model
        if let u = repo.findById(1) {
            let api = repo.convertTo(u)
            io.println("api(1): " + json.stringify(api as Json))
        }

        // upsert + delete
        repo.save(User { id: 1, name: "Cara2", age: 45, pw: "s1" })
        repo.delete(User { id: 2, name: "", age: 0, pw: "" })
        io.println("after upsert+delete: " + repo.findAll().toList().len() + " rows")
    }
}

module App {
    bind QueryProvider -> SqliteProvider as singleton
    bind Db            -> SqliteProvider as singleton
    bind DemoApp       -> Demo
}

entry (app: DemoApp) main(args: String[]) -> Integer {
    app.run()
    return 0
}
