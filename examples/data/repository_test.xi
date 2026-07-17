import "std/data.xi"
import "std/query.xi"
import "std/json.xi"

type User    = { id: Integer, name: String, age: Integer, pw: String }
type UserApi = { id: Integer, name: String, age: Integer }   // no pw on the wire

// The whole repository: supply the provider and the source name. findAll,
// findById, save, delete, deleteById and convertTo/convertFrom are inherited
// defaults from CrudRepository.
class UserRepo implements CrudRepository<Integer, User, UserApi> {
    deps { db: QueryProvider }
    producer getProvider() -> QueryProvider => db
    mapper   source()      -> String        => "users"
}

module App { bind QueryProvider -> MemorySource as singleton }

// The repo is auto-resolved (sole implementor); injected by its generic interface.
test "CRUD + query + convert" (repo: CrudRepository<Integer, User, UserApi>) {
    repo.save(User { id: 1, name: "Cara", age: 44, pw: "s1" })
    repo.save(User { id: 2, name: "Abe",  age: 15, pw: "s2" })
    repo.save(User { id: 3, name: "Bea",  age: 30, pw: "s3" })

    // findAll() carries the repo's provider — a plain .toList() runs it
    let adults = repo.findAll().filter { it.age >= 18 }.sortedBy { it.name }.toList()
    assertEq(adults.len(), 2)
    assertEq(adults.get(0).name, "Bea")

    // findById is findAll().filter{ it.id == id }.first()
    if let u = repo.findById(1) {
        assertEq(u.name, "Cara")
        let api = repo.convertTo(u)                  // default: drops pw
        assertEq(json.stringify(api as Json), "{\"id\":1,\"name\":\"Cara\",\"age\":44}")
    }

    repo.save(User { id: 1, name: "Cara2", age: 45, pw: "x" })   // upsert
    if let u2 = repo.findById(1) { assertEq(u2.name, "Cara2") }

    repo.delete(User { id: 1, name: "", age: 0, pw: "" })
    assert not (repo.findById(1)).has_value
}
