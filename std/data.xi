// std/data — standard repository interfaces over any QueryProvider.
//
// A repository is the persistence boundary for one entity type. Implement
// `CrudRepository<TKey, TEntity, TModel>` on a small class and supply just two
// things: `getProvider()` (which provider backs it) and `source()` (the source
// name). Everything else — findAll, findById, save, delete, deleteById, and the
// entity <-> model conversion — is a default you inherit and may override.
//
//     class UserRepo implements CrudRepository<Integer, User, UserApi> {
//         deps { db: QueryProvider }
//         producer getProvider() -> QueryProvider => db
//         mapper   source()      -> String        => "users"
//     }
//
//     let adults = repo.findAll().filter { it.age >= 18 }.toList()   // uses getProvider()
//     let one    = repo.findById(1)                                  // User?
//
// `findAll()` binds the repository's own provider to the query with `.using`, so
// the composable reads run against it — not a globally-resolved provider. The
// JSON at the provider boundary stays inside these defaults; your repository and
// its callers work in entity types.
//
// Kept un-namespaced so user code can `implements CrudRepository<...>` with bare
// names.
import "std/json.xi"
import "std/query.xi"

// Read side: a queryable source of TEntity, plus entity <-> model conversion.
// Implement getProvider / source; the rest are overridable defaults.
interface Repository<TKey, TEntity, TModel> {
    producer getProvider() -> QueryProvider     // which provider backs this repo
    mapper   source()      -> String            // the source name to query/write

    // findAll binds the repo's provider to the query, so the whole composable
    // chain (filter/sortedBy/take/...) runs against it with a plain `.toList()`.
    producer findAll() -> Query<TEntity> => query.from<TEntity>(source()).using(getProvider())

    // one row by key — just a filtered findAll (entities are keyed by `id`).
    producer findById(id: TKey) -> TEntity? => findAll().filter { it.id == id }.first()

    // Default entity <-> model mapping: a field-matched projection through the
    // derived JSON codecs (fields present in the target are copied by name,
    // extras dropped, missing zeroed). Override either for custom mapping.
    mapper convertTo(e: TEntity) -> TModel   => (e as Json) as TModel
    mapper convertFrom(m: TModel) -> TEntity => (m as Json) as TEntity
}

// Full CRUD: read side plus writes, over the QueryProvider write contract.
// All three are defaults; override any of them.
interface CrudRepository<TKey, TEntity, TModel> extends Repository<TKey, TEntity, TModel> {
    consumer save(e: TEntity) {
        getProvider().remove(source(), "id", e.id as Json)   // upsert: replace by key
        getProvider().insert(source(), e as Json)
    }
    consumer delete(e: TEntity)   => deleteById(e.id)
    consumer deleteById(id: TKey) => getProvider().remove(source(), "id", id as Json)
}
