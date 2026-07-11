// xi-query: reified chains against the in-memory reference provider.
// The chain compiles to a QueryPlan value; collect(provider) runs it and
// decodes the rows into the chain's element type.
import "std/query.xi"
import "std/json.xi"

type User     = { id: Integer, name: String, age: Integer }
type Order    = { userId: Integer, amount: Integer }
type UserView = { who: String, spent: Integer }
type Spend    = { orders: Integer, total: Number }

module App {
    bind QueryProvider -> MemorySource as singleton
    bind RowStore      -> MemorySource as singleton
}

producer seed() -> QueryProvider {
    let store = App.resolve(RowStore)
    store.load("users", json.parse("[{\"id\":1,\"name\":\"Cara\",\"age\":44},{\"id\":2,\"name\":\"Abe\",\"age\":15},{\"id\":3,\"name\":\"Bea\",\"age\":30}]"))
    store.load("orders", json.parse("[{\"userId\":1,\"amount\":10},{\"userId\":3,\"amount\":25},{\"userId\":3,\"amount\":5}]"))
    return App.resolve(QueryProvider)
}

test "filter + sortedBy + take collect typed rows" {
    let db = seed()
    let adults = query.from<User>("users")
        .filter { it.age >= 18 }
        .sortedBy { it.name }
        .take(2)
        .collect(db)
    assertEq(adults.len(), 2)
    assertEq(adults.get(0).name, "Bea")
    assertEq(adults.get(1).name, "Cara")
}

test "map narrows the element type" {
    let db = seed()
    let ages = query.from<User>("users").map { it.age }.sortedBy { it }.collect(db)
    assertEq(ages.len(), 3)
    assertEq(ages.get(0), 15)
    assertEq(ages.get(2), 44)
}

test "captured locals embed as bound values" {
    let db = seed()
    let minAge = 20
    let letter = "C"
    let picked = query.from<User>("users")
        .filter { it.age >= minAge and it.name.startsWith(letter) }
        .collect(db)
    assertEq(picked.len(), 1)
    assertEq(picked.get(0).name, "Cara")
}

test "join pairs rows; map projects a record" {
    let db = seed()
    let views = query.from<User>("users")
        .join(query.from<Order>("orders"), { it.id }, { it.userId })
        .map { UserView { who: it.first.name, spent: it.second.amount } }
        .sortedByDescending { it.spent }
        .collect(db)
    assertEq(views.len(), 3)
    assertEq(views.get(0).who, "Bea")
    assertEq(views.get(0).spent, 25)
}

test "groupBy folds aggregates per key" {
    let db = seed()
    let spend = query.from<Order>("orders")
        .groupBy { it.userId }
        .map { Spend { orders: it.count(), total: it.sum { x => x.amount } } }
        .sortedBy { it.total }
        .collect(db)
    assertEq(spend.len(), 2)
    assertEq(spend.get(0).orders, 1)
    assertClose(spend.get(1).total, 30.0, 1e-9)
}

test "the plan is data: it serializes and round-trips" {
    let plan = query.from<User>("users").filter { it.age > 18 }.take(3).plan
    let back = (json.parse(json.stringify(plan as Json))) as QueryPlan
    assertEq(back.source, "users")
    assertEq(back.stages.len(), 2)
}

test "asQuery roots a plan at a plain List; toList runs it locally" {
    let employees = empty List<User>
    employees.push(User { id: 1, name: "Cara", age: 44 })
    employees.push(User { id: 2, name: "Abe",  age: 15 })
    employees.push(User { id: 3, name: "Bea",  age: 30 })
    let adults = employees.asQuery()
        .filter { it.age >= 18 }
        .sortedBy { it.name }
        .take(2)
        .toList()
    assertEq(adults.len(), 2)
    assertEq(adults.get(0).name, "Bea")
}

test "join and groupBy work between plain lists" {
    let people = empty List<User>
    people.push(User { id: 1, name: "Cara", age: 44 })
    people.push(User { id: 3, name: "Bea",  age: 30 })
    let orders = empty List<Order>
    orders.push(Order { userId: 3, amount: 25 })
    orders.push(Order { userId: 3, amount: 5 })
    orders.push(Order { userId: 1, amount: 10 })
    let spend = orders.asQuery()
        .groupBy { it.userId }
        .map { Spend { orders: it.count(), total: it.sum { x => x.amount } } }
        .sortedByDescending { it.total }
        .toList()
    assertEq(spend.get(0).orders, 2)
    assertClose(spend.get(0).total, 30.0, 1e-9)
    let views = people.asQuery()
        .join(orders.asQuery(), { it.id }, { it.userId })
        .map { UserView { who: it.first.name, spent: it.second.amount } }
        .toList()
    assertEq(views.len(), 3)
}
