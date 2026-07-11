# xi-query — reified queries

A query chain in Xi does not execute where it is written. The compiler turns
the whole chain into a **plan** — a typed tree value — and hands it to a
**provider**, which decides what the plan means: run it in memory, translate
it to SQL, forward it over the wire, or reject what it can't honor. One query
syntax, any backend.

```x
import "std/query.xi"

type User = { id: Integer, name: String, age: Integer }

let adults = query.from<User>("users")
    .filter { it.age >= 18 and it.name.startsWith("A") }
    .sortedBy { it.name }
    .take(10)
    .collect(db)             // -> List<User>, no casts
```

Nothing before `.collect` touches data. The element type threads through the
chain — `query.from<User>` starts it, `.map { it.age }` narrows it to
`Integer`, and `collect` decodes the provider's rows back into the right
type automatically.

## Stages

| Stage | Effect | Element after |
|---|---|---|
| `query.from<T>("src")` | root: the source to query | `T` |
| `.filter { pred }` | keep rows where `pred` holds | unchanged |
| `.map { expr }` | project each row | the expression's type |
| `.sortedBy { key }` / `.sortedByDescending { key }` | order rows | unchanged |
| `.take(n)` / `.drop(n)` | limit / skip | unchanged |
| `.concat(other)` | append another query's rows (same element type) | unchanged |
| `.join(other, { lk }, { rk })` | pair rows whose keys agree | a pair — `it.first` / `it.second` |
| `.groupBy { key }` | group rows by key | a group — `it.key` + aggregates |
| `.collect(provider)` | run the plan | `List<element>` |
| `.plan` | the reified plan value itself | `QueryPlan` |

`from` defaults its source to the type name: `query.from<User>()` queries
`"User"` — providers map source names however they like.

## What a lambda may contain

Query lambdas are **reified, not executed**, so they carry a closed set of
shapes the plan can express:

- the lambda parameter and its fields: `it.age`, `it.addr.city`
- literals, `and or not`, comparisons, `+ - * / %`, `in`, `matches`
- string methods: `contains, startsWith, endsWith, lowercase, uppercase, length`
- **captured locals** — evaluated immediately and embedded as bound values:

```x
let minAge = 18
.filter { it.age >= minAge }        // the VALUE 18 is in the plan, not the name
```

- **record projections** — build a shape per row:

```x
.map { UserView { who: it.name, tag: it.name.lowercase() } }
```

Anything else is a compile-time error at the source line — a typo'd field
(`it.nmae`) reports `type 'User' has no field 'nmae'`, an unknown method names
the supported set.

## join and groupBy

```x
// pair users with their orders; address sides as first/second
let views = query.from<User>("users")
    .join(query.from<Order>("orders"), { it.id }, { it.userId })
    .filter { it.second.amount > 8 }
    .map { UserView { who: it.first.name, spent: it.second.amount } }
    .collect(db)

// aggregate per key: it.key plus count/sum/avg/min/max over the group
let stats = query.from<Order>("orders")
    .groupBy { it.userId }
    .map { Spend { user: it.key, orders: it.count(), total: it.sum { x => x.amount } } }
    .collect(db)
```

Joins are equi-joins (two key lambdas), which keeps them cheap in memory and
translatable everywhere. Joined and grouped rows must be projected with
`.map { ... }` before `.collect`.

## Providers

A provider is any class implementing one interface:

```x
interface QueryProvider {
    producer run(plan: QueryPlan) -> Json    // result rows as a Json array
}
```

`std/query.xi` ships **MemorySource** — the in-memory reference interpreter
every other provider must agree with. Load rows through its `RowStore` view;
bind both views to it `as singleton` and they share one instance:

```x
module App {
    bind QueryProvider -> MemorySource as singleton
    bind RowStore      -> MemorySource as singleton
}

App.resolve(RowStore).load("users", json.parse(rowsText))
let out = query.from<User>("users").filter { it.age > 21 }.collect(App.resolve(QueryProvider))
```

Because the provider is an interface, tests swap a database for MemorySource
with a one-line bind — same queries, no infrastructure.

## The plan is data

`QueryPlan` / `QueryStage` / `QueryExpr` are ordinary sum types
(see `std/query.xi`) — walk them with `match`:

```x
mapper describe(e: QueryExpr) -> String {
    match e {
        QField f -> { return f.path }
        QBin b   -> { return "(" + describe(b.left) + " " + b.op + " " + describe(b.right) + ")" }
        QParam v -> { return json.stringify(v.value) }
        ...
    }
}
```

And they serialize — `plan as Json` / `json as QueryPlan` round-trip — so a
plan can be logged, cache-keyed, or shipped to a remote query service.

Node kinds: `QLit, QField, QParam, QBin, QUn, QCall, QAgg, QRecord`.
Stage kinds: `QFilter, QProject, QSortBy, QTake, QDrop, QConcat, QJoin, QGroupBy`.
Captured values arrive as `QParam` nodes — already evaluated, ready to bind.

## SQL rendering (std/sql.xi)

`sqlRender(plan, dialect)` folds a plan into one SELECT with **bound
parameters** (values are never spliced into the text):

```x
import "std/sql.xi"

let st = (sqlRender(q.plan, SqliteDialect {} as SqlDialect))?
// st.text    SELECT * FROM "users" WHERE ("age" >= ?) ORDER BY "name" LIMIT 10
// st.params  [18]
```

Dialects are an interface — `SqliteDialect`, `PostgresDialect` (`$1`
placeholders), `MysqlDialect` are bundled; implement `SqlDialect` to add your
own. A dialect that can't translate a reified method call fails the render
with the method named, so untranslatable queries are a clear error, not a
silent wrong answer.

| Hook | Decides |
|---|---|
| `placeholder(n)` | `?` vs `$n` |
| `quoteIdent(name)` | `"col"` vs `` `col` `` |
| `callSql(method, recv, args)` | how string methods translate ("" = can't) |
| `regexpExpr(recv, pattern)` | the `matches` operator |
| `limitSql(...)` | LIMIT/OFFSET spelling |

## Scope notes

- A plan value is built once per chain; branch by building separate chains.
- Joining an already joined or grouped query isn't supported — project it
  first.
- MemorySource's stage-by-stage interpretation is the reference semantics;
  a translating provider may fold stages into one statement only where the
  meaning is preserved (the plan records stage order verbatim).
