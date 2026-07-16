// std/data — standard repository interfaces over any QueryProvider.
//
// A repository is the persistence boundary for one entity type. Implement
// `CrudRepository<TKey, TEntity, TModel>` on a small class that supplies a
// `QueryProvider` and the source name; the reads return a `Query<TEntity>` you
// compose with the full query API, and `convertTo` / `convertFrom` map the
// entity to and from an external model (a DTO) — by default a field-matched
// projection through JSON, overridable per method.
//
//     class UserRepo implements CrudRepository<Integer, User, UserApi> {
//         deps { db: QueryProvider }
//         state { source: String = "users" }
//         producer findAll() -> Query<User> => query.from<User>(this.source)
//         producer findById(id: Integer) -> User? { … }
//         consumer save(e: User)          { db.remove(this.source, "id", json.int(e.id))  db.insert(this.source, e as Json) }
//         consumer delete(e: User)        { deleteById(e.id) }
//         consumer deleteById(id: Integer) { db.remove(this.source, "id", json.int(id)) }
//         // convertTo / convertFrom inherited as defaults (override to customize)
//     }
//
//     module App { bind QueryProvider -> SqliteProvider as singleton }   // or MemorySource in tests
//     let adults = repo.findAll().filter { it.age >= 18 }.toList()       // runs via the bound provider
//
// Kept un-namespaced so user code can `implements CrudRepository<...>` with bare
// names.
import "std/json.xi"
import "std/query.xi"

// Read side: a queryable source of TEntity, plus entity <-> model conversion.
interface Repository<TKey, TEntity, TModel> {
    producer findAll() -> Query<TEntity>
    producer findById(id: TKey) -> TEntity?

    // Default entity <-> model mapping: a field-matched projection through the
    // derived JSON codecs (fields present in the target are copied by name,
    // extras dropped, missing zeroed). Override either for custom mapping.
    mapper convertTo(e: TEntity) -> TModel   => (e as Json) as TModel
    mapper convertFrom(m: TModel) -> TEntity => (m as Json) as TEntity
}

// Full CRUD: read side plus writes, over the QueryProvider write contract.
interface CrudRepository<TKey, TEntity, TModel> extends Repository<TKey, TEntity, TModel> {
    consumer save(e: TEntity)
    consumer delete(e: TEntity)
    consumer deleteById(id: TKey)
}
