import "std/json.xi"
type User    = { id: Integer, name: String, pw: String }
type UserApi = { id: Integer, name: String }

interface Reader<TKey, TEntity, TModel> {
    mapper getById(id: TKey) -> TEntity
    mapper convertTo(e: TEntity) -> TModel => (e as Json) as TModel        // default, self-free
    mapper convertFrom(m: TModel) -> TEntity => (m as Json) as TEntity     // default, self-free
}
interface Crud<TKey, TEntity, TModel> extends Reader<TKey, TEntity, TModel> {
    mapper label() -> String => "crud"                                     // default, no type vars
}
class UserRepo implements Crud<Integer, User, UserApi> {
    deps {}
    mapper getById(id: Integer) -> User => User { id: id, name: "Ada", pw: "secret" }
}

interface App2 { mapper run() -> String }
class Runner implements App2 {
    deps { repo: Crud<Integer, User, UserApi> }
    mapper run() -> String {
        let u = repo.getById(7)                 // -> User
        let api = repo.convertTo(u)             // default: entity -> model (drops pw)
        let back = repo.convertFrom(api)        // default: model -> entity
        return repo.label() + " " + api.name + " id=" + api.id + " pwLeft=[" + back.pw + "]"
    }
}
module App { bind App2 -> Runner as singleton }

test "generic extends + self-free defaults (convert via Json bridge)" {
    let r = App.resolve(App2)
    assertEq(r.run(), "crud Ada id=7 pwLeft=[]")
}
