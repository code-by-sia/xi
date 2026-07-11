// xi-query: rendering plans to SQL with dialects (std/sql.xi).
// Values captured in the plan become bound parameters — never spliced text.
import "std/query.xi"
import "std/sql.xi"
import "std/json.xi"

type User  = { id: Integer, name: String, age: Integer }
type Order = { userId: Integer, amount: Integer }
type Spend = { orders: Integer, total: Number }

test "filter + sort + limit folds into one SELECT with bound params" {
    let minAge = 18
    let plan = query.from<User>("users")
        .filter { it.age >= minAge and it.name.startsWith("A") }
        .sortedBy { it.name }
        .take(5)
        .plan
    let st = (sqlRender(plan, SqliteDialect {} as SqlDialect)).value
    assertEq(st.text, "SELECT * FROM \"users\" WHERE ((\"age\" >= ?) AND \"name\" LIKE ? || '%') ORDER BY \"name\" LIMIT 5")
    assertEq(json.stringify(st.params), "[18,\"A\"]")
}

test "dialects differ where engines differ" {
    let plan = query.from<User>("users").filter { it.age > 21 }.plan
    let pg = (sqlRender(plan, PostgresDialect {} as SqlDialect)).value
    assertEq(pg.text, "SELECT * FROM \"users\" WHERE (\"age\" > $1)")
    let plan2 = query.from<User>("users").filter { it.age > 21 }.plan
    let my = (sqlRender(plan2, MysqlDialect {} as SqlDialect)).value
    assertEq(my.text, "SELECT * FROM `users` WHERE (`age` > ?)")
}

test "groupBy renders GROUP BY with aggregate projection" {
    let plan = query.from<Order>("orders")
        .groupBy { it.userId }
        .map { Spend { orders: it.count(), total: it.sum { x => x.amount } } }
        .plan
    let st = (sqlRender(plan, SqliteDialect {} as SqlDialect)).value
    assertEq(st.text, "SELECT COUNT(*) AS \"orders\", SUM(\"amount\") AS \"total\" FROM \"orders\" GROUP BY \"userId\"")
}

test "concat renders UNION ALL" {
    let plan = query.from<User>("kids").concat(query.from<User>("elders")).plan
    let st = (sqlRender(plan, SqliteDialect {} as SqlDialect)).value
    assertEq(st.text, "SELECT * FROM \"kids\" UNION ALL SELECT * FROM \"elders\"")
}

test "a stage after a finished shape wraps a subquery" {
    let plan = query.from<User>("users").take(10).filter { it.age > 30 }.plan
    let st = (sqlRender(plan, SqliteDialect {} as SqlDialect)).value
    assertEq(st.text, "SELECT * FROM (SELECT * FROM \"users\" LIMIT 10) AS _q0 WHERE (\"age\" > ?)")
}
