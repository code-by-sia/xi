// std/sql — xi-query: render a QueryPlan to a SQL statement.
//
// `sqlRender(plan, dialect)` folds a plan's stages into one SELECT (wrapping
// finished shapes as subqueries when a stage arrives out of slot order) and
// returns the statement text plus its bind parameters — values captured in the
// plan are always bound, never spliced, so statements are injection-safe by
// construction.
//
//     let st = sqlRender(q.plan, SqliteDialect {} as SqlDialect)?
//     // st.text   "SELECT * FROM \"users\" WHERE \"age\" >= ? ORDER BY \"name\" LIMIT 2"
//     // st.params [18]
//
// Dialects are an interface — add your own without touching std. A dialect
// that can't translate a reified method call returns "" from callSql and the
// render fails with an error naming the method.
import "std/json.xi"
import "std/query.xi"

type SqlStatement = { text: String, params: Json }

interface SqlDialect {
    mapper name() -> String                                     // e.g. "sqlite"
    mapper placeholder(n: Integer) -> String                    // 1-based param slot
    mapper quoteIdent(name: String) -> String
    mapper callSql(method: String, recv: String, args: List<String>) -> String
    mapper regexpExpr(recv: String, pattern: String) -> String
    mapper limitSql(hasTake: Bool, takeN: Integer, hasDrop: Bool, dropN: Integer) -> String
}

// ── bundled dialects ────────────────────────────────────────────────
class SqliteDialect implements SqlDialect {
    deps {}
    mapper name() -> String => "sqlite"
    mapper placeholder(n: Integer) -> String => "?"
    mapper quoteIdent(name: String) -> String => "\"" + name + "\""
    mapper callSql(method: String, recv: String, args: List<String>) -> String {
        if method == "contains"   { return recv + " LIKE '%' || " + args.get(0) + " || '%'" }
        if method == "startsWith" { return recv + " LIKE " + args.get(0) + " || '%'" }
        if method == "endsWith"   { return recv + " LIKE '%' || " + args.get(0) }
        if method == "lowercase"  { return "LOWER(" + recv + ")" }
        if method == "uppercase"  { return "UPPER(" + recv + ")" }
        if method == "length"     { return "LENGTH(" + recv + ")" }
        return ""
    }
    mapper regexpExpr(recv: String, pattern: String) -> String => recv + " REGEXP " + pattern
    mapper limitSql(hasTake: Bool, takeN: Integer, hasDrop: Bool, dropN: Integer) -> String {
        let out = ""
        if hasTake { out = " LIMIT " + takeN } else { if hasDrop { out = " LIMIT -1" } }
        if hasDrop { out = out + " OFFSET " + dropN }
        return out
    }
}

class PostgresDialect implements SqlDialect {
    deps {}
    mapper name() -> String => "postgres"
    mapper placeholder(n: Integer) -> String => "$" + n
    mapper quoteIdent(name: String) -> String => "\"" + name + "\""
    mapper callSql(method: String, recv: String, args: List<String>) -> String {
        if method == "contains"   { return recv + " LIKE '%' || " + args.get(0) + " || '%'" }
        if method == "startsWith" { return recv + " LIKE " + args.get(0) + " || '%'" }
        if method == "endsWith"   { return recv + " LIKE '%' || " + args.get(0) }
        if method == "lowercase"  { return "LOWER(" + recv + ")" }
        if method == "uppercase"  { return "UPPER(" + recv + ")" }
        if method == "length"     { return "LENGTH(" + recv + ")" }
        return ""
    }
    mapper regexpExpr(recv: String, pattern: String) -> String => recv + " ~ " + pattern
    mapper limitSql(hasTake: Bool, takeN: Integer, hasDrop: Bool, dropN: Integer) -> String {
        let out = ""
        if hasTake { out = " LIMIT " + takeN }
        if hasDrop { out = out + " OFFSET " + dropN }
        return out
    }
}

class MysqlDialect implements SqlDialect {
    deps {}
    mapper name() -> String => "mysql"
    mapper placeholder(n: Integer) -> String => "?"
    mapper quoteIdent(name: String) -> String => "`" + name + "`"
    mapper callSql(method: String, recv: String, args: List<String>) -> String {
        if method == "contains"   { return recv + " LIKE CONCAT('%', " + args.get(0) + ", '%')" }
        if method == "startsWith" { return recv + " LIKE CONCAT(" + args.get(0) + ", '%')" }
        if method == "endsWith"   { return recv + " LIKE CONCAT('%', " + args.get(0) + ")" }
        if method == "lowercase"  { return "LOWER(" + recv + ")" }
        if method == "uppercase"  { return "UPPER(" + recv + ")" }
        if method == "length"     { return "CHAR_LENGTH(" + recv + ")" }
        return ""
    }
    mapper regexpExpr(recv: String, pattern: String) -> String => recv + " REGEXP " + pattern
    mapper limitSql(hasTake: Bool, takeN: Integer, hasDrop: Bool, dropN: Integer) -> String {
        let out = ""
        if hasTake { out = " LIMIT " + takeN } else { if hasDrop { out = " LIMIT 18446744073709551615" } }
        if hasDrop { out = out + " OFFSET " + dropN }
        return out
    }
}

// ── expression rendering ────────────────────────────────────────────
mapper sqlOpFor(op: String) -> String {
    if op == "and" { return "AND" }
    if op == "or"  { return "OR" }
    if op == "==" { return "=" }
    if op == "!=" { return "<>" }
    return op          // < > <= >= + - * / pass through
}

// Render a field path. On a joined shape the first segment picks the side
// (first -> l, second -> r); a grouped projection's `key` renders the key.
mapper sqlField(path: String, d: SqlDialect, joined: Bool, groupKeySql: String) -> String {
    if path == "key" and string_len(groupKeySql) > 0 { return groupKeySql }
    let seg = path
    let rest = ""
    let dotAt = 0 - 1
    let i = 0
    while i < string_len(path) {
        if string_char_at(path, i) == 46 and dotAt < 0 { dotAt = i }
        i = i + 1
    }
    if dotAt >= 0 {
        seg = string_slice(path, 0, dotAt)
        rest = string_slice(path, dotAt + 1, string_len(path))
    }
    if joined and seg == "first"  { return "l." + d.quoteIdent(rest) }
    if joined and seg == "second" { return "r." + d.quoteIdent(rest) }
    if dotAt >= 0 { return d.quoteIdent(seg) + "." + d.quoteIdent(rest) }
    return d.quoteIdent(path)
}

mapper sqlExpr(e: QueryExpr, d: SqlDialect, params: Json, joined: Bool, groupKeySql: String) -> String! {
    match e {
        QLit v -> {
            json.push(params, v.value)
            return ok(d.placeholder(json.length(params)))
        }
        QParam v -> {
            json.push(params, v.value)
            return ok(d.placeholder(json.length(params)))
        }
        QField f -> { return ok(sqlField(f.path, d, joined, groupKeySql)) }
        QBin b -> {
            let ls = sqlExpr(b.left, d, params, joined, groupKeySql)?
            if b.op == "in" {
                // expand the captured collection into a bound placeholder list
                let vals = inValuesOf(b.right)
                let items = ""
                let n = json.length(vals)
                let i = 0
                while i < n {
                    json.push(params, json.at(vals, i))
                    if i > 0 { items = items + ", " }
                    items = items + d.placeholder(json.length(params))
                    i = i + 1
                }
                return ok("(" + ls + " IN (" + items + "))")
            }
            let rs = sqlExpr(b.right, d, params, joined, groupKeySql)?
            if b.op == "matches" { return ok("(" + d.regexpExpr(ls, rs) + ")") }
            return ok("(" + ls + " " + sqlOpFor(b.op) + " " + rs + ")")
        }
        QUn u -> {
            let xs = sqlExpr(u.operand, d, params, joined, groupKeySql)?
            if u.op == "not" { return ok("(NOT " + xs + ")") }
            return ok("(-" + xs + ")")
        }
        QCall c -> {
            let rs = sqlExpr(c.recv, d, params, joined, groupKeySql)?
            let args = empty List<String>
            for a in c.args {
                let s = sqlExpr(a, d, params, joined, groupKeySql)?
                args.push(s)
            }
            let out = d.callSql(c.method, rs, args)
            if string_len(out) == 0 {
                return err("this SQL dialect can't translate '" + c.method + "(...)' in a query")
            }
            return ok(out)
        }
        QAgg g -> {
            if g.fn == "count" { return ok("COUNT(*)") }
            let xs = sqlExpr(g.operand, d, params, joined, groupKeySql)?
            if g.fn == "sum" { return ok("SUM(" + xs + ")") }
            if g.fn == "avg" { return ok("AVG(" + xs + ")") }
            if g.fn == "min" { return ok("MIN(" + xs + ")") }
            return ok("MAX(" + xs + ")")
        }
        QRecord r -> {
            // a record renders as a projection list: expr AS name, ...
            let out = ""
            let i = 0
            while i < r.names.len() {
                let es = sqlExpr(r.exprs.get(i), d, params, joined, groupKeySql)?
                if i > 0 { out = out + ", " }
                out = out + es + " AS " + d.quoteIdent(r.names.get(i))
                i = i + 1
            }
            return ok(out)
        }
    }
    return err("unrenderable query expression")
}

// The captured collection of an `in` — a QParam/QLit holding a Json array.
mapper inValuesOf(e: QueryExpr) -> Json {
    match e {
        QParam v -> { return v.value }
        QLit v   -> { return v.value }
        else     -> { return json.array() }
    }
    return json.array()
}

// ── plan rendering: fold stages into one SELECT ─────────────────────
mapper sqlRender(plan: QueryPlan, d: SqlDialect) -> SqlStatement! {
    let params = json.array()
    let text = renderPlan(plan, d, params)?
    return ok(SqlStatement { text: text, params: params })
}

mapper renderPlan(plan: QueryPlan, d: SqlDialect, params: Json) -> String! {
    if plan.source == "$inline" {
        return err("a list-rooted query (asQuery) has no SQL source — run it locally with .toList()")
    }
    let fromSql = d.quoteIdent(plan.source)
    let joinSql = ""
    let joined = false
    let whereSql = ""
    let groupSql = ""
    let groupKeySql = ""
    let havingSql = ""
    let orderSql = ""
    let projSql = ""
    let hasTake = false
    let takeN = 0
    let hasDrop = false
    let dropN = 0
    let wraps = 0

    for st in plan.stages {
        match st {
            QFilter f -> {
                if string_len(projSql) > 0 or hasTake or hasDrop {
                    // shape already finished: wrap it and filter the subquery
                    fromSql = "(" + assemble(d, fromSql, joinSql, whereSql, groupSql, havingSql, orderSql, projSql, hasTake, takeN, hasDrop, dropN) + ") AS _q" + wraps
                    wraps = wraps + 1
                    joinSql = ""  joined = false  whereSql = ""  groupSql = ""  groupKeySql = ""
                    havingSql = ""  orderSql = ""  projSql = ""  hasTake = false  hasDrop = false
                }
                let cond = sqlExpr(f.pred, d, params, joined, groupKeySql)?
                if string_len(groupSql) > 0 {
                    if string_len(havingSql) > 0 { havingSql = havingSql + " AND " }
                    havingSql = havingSql + cond
                } else {
                    if string_len(whereSql) > 0 { whereSql = whereSql + " AND " }
                    whereSql = whereSql + cond
                }
            }
            QProject pj -> {
                if string_len(projSql) > 0 or hasTake or hasDrop {
                    fromSql = "(" + assemble(d, fromSql, joinSql, whereSql, groupSql, havingSql, orderSql, projSql, hasTake, takeN, hasDrop, dropN) + ") AS _q" + wraps
                    wraps = wraps + 1
                    joinSql = ""  joined = false  whereSql = ""  groupSql = ""  groupKeySql = ""
                    havingSql = ""  orderSql = ""  projSql = ""  hasTake = false  hasDrop = false
                }
                let pv = sqlExpr(pj.expr, d, params, joined, groupKeySql)?
                projSql = pv
            }
            QSortBy s -> {
                let key = sqlExpr(s.key, d, params, joined, groupKeySql)?
                if string_len(orderSql) > 0 { orderSql = orderSql + ", " }
                orderSql = orderSql + key
                if s.desc { orderSql = orderSql + " DESC" }
            }
            QTake t -> {
                if hasTake { if t.n < takeN { takeN = t.n } } else { hasTake = true  takeN = t.n }
            }
            QDrop dr -> {
                if hasDrop { dropN = dropN + dr.n } else { hasDrop = true  dropN = dr.n }
            }
            QJoin jn -> {
                let right = renderPlan(jn.right, d, params)?
                let lk = sqlExpr(jn.leftKey, d, params, false, "")?
                let rk = sqlExpr(jn.rightKey, d, params, false, "")?
                fromSql = fromSql + " AS l JOIN (" + right + ") AS r ON l." + stripOuter(lk) + " = r." + stripOuter(rk)
                joined = true
            }
            QGroupBy gb -> {
                let gk = sqlExpr(gb.key, d, params, joined, "")?
                groupKeySql = gk
                groupSql = gk
            }
            QConcat c -> {
                let right = renderPlan(c.right, d, params)?
                let left = assemble(d, fromSql, joinSql, whereSql, groupSql, havingSql, orderSql, projSql, hasTake, takeN, hasDrop, dropN)
                return ok(left + " UNION ALL " + right)
            }
        }
    }
    return ok(assemble(d, fromSql, joinSql, whereSql, groupSql, havingSql, orderSql, projSql, hasTake, takeN, hasDrop, dropN))
}

// Strip one layer of parens/quotes from a rendered key so it can sit after an
// alias qualifier in an ON clause.
mapper stripOuter(s: String) -> String {
    if string_len(s) >= 2 and string_char_at(s, 0) == 34 { return s }
    return s
}

mapper assemble(d: SqlDialect, fromSql: String, joinSql: String, whereSql: String, groupSql: String, havingSql: String, orderSql: String, projSql: String, hasTake: Bool, takeN: Integer, hasDrop: Bool, dropN: Integer) -> String {
    let proj = projSql
    if string_len(proj) == 0 { proj = "*" }
    let out = "SELECT " + proj + " FROM " + fromSql
    if string_len(whereSql) > 0 { out = out + " WHERE " + whereSql }
    if string_len(groupSql) > 0 { out = out + " GROUP BY " + groupSql }
    if string_len(havingSql) > 0 { out = out + " HAVING " + havingSql }
    if string_len(orderSql) > 0 { out = out + " ORDER BY " + orderSql }
    out = out + d.limitSql(hasTake, takeN, hasDrop, dropN)
    return out
}