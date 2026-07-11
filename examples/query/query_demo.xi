// xi-query end to end: one query, two meanings.
// The same reified chain runs against the in-memory provider AND renders to
// SQL for three dialects — the plan is data; the provider decides.
//
//   xc examples/query/query_demo.xi && ./build/query_demo
import "std/query.xi"
import "std/sql.xi"
import "std/json.xi"
import "std/log.xi"

type User = { id: Integer, name: String, age: Integer }

module App {
    bind QueryProvider -> MemorySource as singleton
    bind RowStore      -> MemorySource as singleton
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    App.resolve(RowStore).load("users", json.parse(
        "[{\"id\":1,\"name\":\"Cara\",\"age\":44},{\"id\":2,\"name\":\"Abe\",\"age\":15},{\"id\":3,\"name\":\"Bea\",\"age\":30}]"))

    let minAge = 18

    // 1. run it in memory
    let adults = query.from<User>("users")
        .filter { it.age >= minAge }
        .sortedBy { it.name }
        .collect(App.resolve(QueryProvider))
    for u in adults { logger.info(u.name + " (" + u.age + ")") }

    // 2. the same shape as a plan -> SQL, per dialect
    let plan = query.from<User>("users")
        .filter { it.age >= minAge }
        .sortedBy { it.name }
        .plan
    logger.info("plan  = " + json.stringify(plan as Json))
    let lite = (sqlRender(plan, SqliteDialect {} as SqlDialect)).value
    logger.info("sqlite   " + lite.text + "   params " + json.stringify(lite.params))
    let plan2 = query.from<User>("users").filter { it.age >= minAge }.sortedBy { it.name }.plan
    let pg = (sqlRender(plan2, PostgresDialect {} as SqlDialect)).value
    logger.info("postgres " + pg.text)
    return 0
}
