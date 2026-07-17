# Repository - persistence over any provider

A repository is the persistence boundary for one entity type. `std/data` gives
you two generic interfaces: `Repository<TKey, TEntity, TModel>` for the read
side, and `CrudRepository<TKey, TEntity, TModel>` which adds writes. To use one,
implement it on a small class and supply just two things - which provider backs
it (`getProvider`) and the source name (`source`). Everything else is an
overridable default.

```x
import "std/data.xi"

type User    = { id: Integer, name: String, age: Integer, pw: String }
type UserApi = { id: Integer, name: String, age: Integer }   // no pw on the wire

class UserRepo implements CrudRepository<Integer, User, UserApi> {
    deps { db: QueryProvider }
    producer getProvider() -> QueryProvider => db
    mapper   source()      -> String        => "users"
}
```

That is the whole repository. `findAll`, `findById`, `save`, `delete`,
`deleteById`, and `convertTo` / `convertFrom` are inherited defaults.

```x
let adults = repo.findAll().filter { it.age >= 18 }.sortedBy { it.name }.toList()
let one    = repo.findById(1)            // User?
repo.save(User { id: 1, name: "Cara", age: 44, pw: "s1" })
repo.delete(existing)
```

## How findAll knows its provider

`findAll()` binds the repository's own provider to the query with `.using`:

```x
producer findAll() -> Query<TEntity> => query.from<TEntity>(source()).using(getProvider())
```

`.using(provider)` attaches a provider to the query value, so the composable
chain that follows runs against *that* provider when you call a terminal - no
globally-resolved provider, no magic. `findById` is then just a filtered
`findAll`:

```x
producer findById(id: TKey) -> TEntity? => findAll().filter { it.id == id }.first()
```

Because the provider rides along on the query, `findById` never mentions a
provider itself - it inherits the one `findAll` bound.

## The interfaces

```x
interface Repository<TKey, TEntity, TModel> {
    producer getProvider() -> QueryProvider     // you implement
    mapper   source()      -> String            // you implement

    producer findAll() -> Query<TEntity> => query.from<TEntity>(source()).using(getProvider())
    producer findById(id: TKey) -> TEntity? => findAll().filter { it.id == id }.first()

    mapper convertTo(e: TEntity) -> TModel   => (e as Json) as TModel
    mapper convertFrom(m: TModel) -> TEntity => (m as Json) as TEntity
}

interface CrudRepository<TKey, TEntity, TModel> extends Repository<TKey, TEntity, TModel> {
    consumer save(e: TEntity) {
        getProvider().remove(source(), "id", e.id as Json)   // upsert: replace by key
        getProvider().insert(source(), e as Json)
    }
    consumer delete(e: TEntity)   => deleteById(e.id)
    consumer deleteById(id: TKey) => getProvider().remove(source(), "id", id as Json)
}
```

The three type parameters are the key type, the stored entity type, and an
external **model** type (a DTO) used at the boundary. Every method above except
`getProvider` / `source` has a default - override any of them.

| Method | Kind | Purpose |
|---|---|---|
| `getProvider()` | you implement | the provider backing this repo |
| `source()` | you implement | the source name to query and write |
| `findAll()` | default | a provider-bound `Query<TEntity>`, ready to filter |
| `findById(id)` | default | `findAll().filter { it.id == id }.first()` |
| `save(e)` | default | insert or replace by key |
| `delete(e)` / `deleteById(id)` | default | remove by key |
| `convertTo(e)` / `convertFrom(m)` | default | entity ↔ model mapping |

Entities are keyed by an `id` field (that is the convention `findById` /
`deleteById` rely on).

## Entity and model conversion

`convertTo` / `convertFrom` default to a field-matched projection through the
derived JSON codecs. Fields present in the target are copied by name, extras are
dropped, and anything missing is zeroed - so a `User` with a `pw` field becomes a
`UserApi` without it:

```x
let api = repo.convertTo(user)          // pw dropped
```

Override either when the mapping is not a straight field match:

```x
mapper convertTo(e: User) -> UserApi => UserApi { id: e.id, name: e.name.toUpper(), age: e.age }
```

The JSON at the provider boundary stays inside these defaults; your repository
class and its callers work in entity types, not `Json`.

## Binding a provider

`getProvider()` returns a `QueryProvider`; bind whichever one you want. The
repository does not change.

```x
module App {
    bind QueryProvider -> SqliteProvider as singleton   // or MemorySource in tests
}
```

### Selecting a provider by name

When several providers are in scope, a dependency guard picks one by identity -
`QueryProvider` reports a `name()` (like `SqlDialect.name()`), so a repository can
ask for a specific backend without a `bind`:

```x
class UserRepo implements CrudRepository<Integer, User, UserApi> {
    deps { db: QueryProvider where db.name() == "sqlite" }
    producer getProvider() -> QueryProvider => db
    mapper   source()      -> String        => "users"
}
```

The guard is evaluated over each candidate in scope (the bundled `MemorySource`
names itself `"memory"`); the first match is injected. See
[`examples/data/provider_where_test.xi`](https://github.com/code-by-sia/xi/tree/main/examples/data).

### Testing with MemorySource

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

`Repository` and `CrudRepository` are **generic interfaces** with default method
bodies. Xi resolves them by monomorphization: for each concrete
`implements CrudRepository<Integer, User, UserApi>`, the compiler synthesizes a
non-generic interface with the type parameters substituted, and **materializes**
each un-overridden default into your class so its body can call sibling methods
on `this` (`getProvider`, `source`, `findAll`). Vtables, casters, and dependency
injection all work unchanged. See [Generics](language-guide.md#generics).
