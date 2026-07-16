import "std/data.xi"
import "std/query.xi"
import "std/json.xi"

type User    = { id: Integer, name: String, age: Integer, pw: String }
type UserApi = { id: Integer, name: String, age: Integer }   // no pw on the wire

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
    // convertTo / convertFrom inherited as defaults
}

module App { bind QueryProvider -> MemorySource as singleton }

// The repo is auto-resolved (sole implementor); injected by its generic interface.
test "CRUD + query + convert" (repo: CrudRepository<Integer, User, UserApi>) {
    repo.save(User { id: 1, name: "Cara", age: 44, pw: "s1" })
    repo.save(User { id: 2, name: "Abe",  age: 15, pw: "s2" })
    repo.save(User { id: 3, name: "Bea",  age: 30, pw: "s3" })

    let adults = repo.findAll().filter { it.age >= 18 }.sortedBy { it.name }.toList()
    assertEq(adults.len(), 2)
    assertEq(adults.get(0).name, "Bea")

    let u = repo.findById(1)
    assert u.has_value
    assertEq(u.value.name, "Cara")

    let api = repo.convertTo(u.value)                    // default: drops pw
    assertEq(json.stringify(api as Json), "{\"id\":1,\"name\":\"Cara\",\"age\":44}")

    repo.save(User { id: 1, name: "Cara2", age: 45, pw: "x" })   // upsert
    assertEq((repo.findById(1)).value.name, "Cara2")

    repo.delete(User { id: 1, name: "", age: 0, pw: "" })
    assert not (repo.findById(1)).has_value
}
