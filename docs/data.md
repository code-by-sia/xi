# Repository - persistence over any provider

A repository is the persistence boundary for one entity type. `std/data` gives
you two generic interfaces to implement on a small class:
`Repository<TKey, TEntity, TModel>` for the read side, and
`CrudRepository<TKey, TEntity, TModel>` which adds writes. The reads return a
[`Query`](query.md) you compose with the full query API, and the writes go
through the same [`QueryProvider`](query.md) contract, so one repository runs
against an in-memory source in tests and a real database in production without
changing a line.

```x
import "std/data.xi"

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
    // convertTo / convertFrom inherited as defaults (override to customize)
}
```

`findAll()` returns a query, not a list, so callers compose before running:

```x
let adults = repo.findAll()
    .filter { it.age >= 18 }
    .sortedBy { it.name }
    .toList()                     // runs through the bound provider
```

## The interfaces

```x
interface Repository<TKey, TEntity, TModel> {
    producer findAll() -> Query<TEntity>
    producer findById(id: TKey) -> TEntity?

    mapper convertTo(e: TEntity) -> TModel   => (e as Json) as TModel
    mapper convertFrom(m: TModel) -> TEntity => (m as Json) as TEntity
}

interface CrudRepository<TKey, TEntity, TModel> extends Repository<TKey, TEntity, TModel> {
    consumer save(e: TEntity)
    consumer delete(e: TEntity)
    consumer deleteById(id: TKey)
}
```

The three type parameters are the key type, the stored entity type, and an
external **model** type (a DTO) used at the boundary.

| Method | Kind | Purpose |
|---|---|---|
| `findAll()` | read | a `Query<TEntity>` over the whole source, ready to filter |
| `findById(id)` | read | one entity or `none` |
| `save(e)` | write | insert or replace by key |
| `delete(e)` / `deleteById(id)` | write | remove by key |
| `convertTo(e)` | map | entity to model |
| `convertFrom(m)` | map | model to entity |

## Entity and model conversion

`convertTo` / `convertFrom` come with default bodies: a field-matched projection
through the derived JSON codecs. Fields present in the target are copied by name,
extras are dropped, and anything missing is zeroed. This is how a `User` with a
`pw` field becomes a `UserApi` without it:

```x
let api = repo.convertTo(user)          // pw dropped
```

Override either method when the mapping is not a straight field match:

```x
mapper convertTo(e: User) -> UserApi => UserApi { id: e.id, name: e.name.toUpper(), age: e.age }
```

## Binding a provider

The repository holds a `QueryProvider` and calls `run` / `insert` / `remove` on
it. Bind whichever provider you want; the repository does not change.

```x
module App {
    bind QueryProvider -> SqliteProvider as singleton   // or MemorySource in tests
}
```

`MemorySource` from `std/query` implements the full read and write contract, so
tests need no database:

```x
test "CRUD + query" (repo: CrudRepository<Integer, User, UserApi>) {
    repo.save(User { id: 1, name: "Cara", age: 44, pw: "s1" })
    repo.save(User { id: 2, name: "Abe",  age: 15, pw: "s2" })

    let adults = repo.findAll().filter { it.age >= 18 }.toList()
    assertEq(adults.len(), 1)

    if let u = repo.findById(1) { assertEq(u.name, "Cara") }
}
```

The [`examples/data`](https://github.com/code-by-sia/xi/tree/main/examples/data)
directory has the full in-memory test and a SQLite-backed demo that persists
through a real `libsqlite3` connection.

## Generics

`Repository` and `CrudRepository` are **generic interfaces** - the first in the
standard library. Xi resolves them by monomorphization: for each concrete
`implements CrudRepository<Integer, User, UserApi>`, the compiler synthesizes a
non-generic interface with the type parameters substituted, so vtables, casters,
and dependency injection all work unchanged. See
[Generics](language-guide.md#generics) in the language guide.
