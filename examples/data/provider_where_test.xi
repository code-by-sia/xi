// Selecting a repository's provider with a `where` guard.
//
// A repository holds a `QueryProvider`; when several implement the contract, a
// dependency guard picks the right one by identity. Here two providers are in
// scope — the bundled in-memory `MemorySource` (name "memory") and the
// `SqliteProvider` below (name "sqlite") — and the repository asks for the one
// that names itself "sqlite". No `bind QueryProvider` is needed; the guard
// chooses among the candidates in scope.
import "std/data.xi"
import "std/query.xi"
import "std/json.xi"

type User = { id: Integer, name: String, age: Integer }

// A "sqlite" provider (in-memory here so the example stays self-contained — the
// point is the name-based selection, not the backend). It names itself and, via
// the same kind of guard, forwards the contract to the "memory" provider.
class SqliteProvider implements QueryProvider {
    deps { store: QueryProvider where store.name() == "memory" }
    mapper   name() -> String => "sqlite"
    producer run(plan: QueryPlan) -> Json => store.run(plan)
    consumer insert(source: String, row: Json)             { store.insert(source, row) }
    consumer remove(source: String, key: String, id: Json) { store.remove(source, key, id) }
}

class UserRepo implements CrudRepository<Integer, User, User> {
    // Of the QueryProviders in scope, take the one whose name() is "sqlite".
    deps { db: QueryProvider where db.name() == "sqlite" }
    producer getProvider() -> QueryProvider => db
    mapper   source()      -> String        => "users"
}

module App {}

test "repository selects the sqlite provider by name" (repo: CrudRepository<Integer, User, User>) {
    assertEq(repo.getProvider().name(), "sqlite")     // guard picked SqliteProvider, not MemorySource

    repo.save(User { id: 1, name: "Cara", age: 44 })
    repo.save(User { id: 2, name: "Abe",  age: 15 })

    let adults = repo.findAll().filter { it.age >= 18 }.toList()
    assertEq(adults.len(), 1)
    assertEq(adults.get(0).name, "Cara")
}
