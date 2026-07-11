// std/query — xi-query: reified query plans and the provider contract.
//
// A chain rooted at `query.from<T>("source")` does not execute — the compiler
// reifies every stage into a QueryPlan value, a typed tree. `collect(provider)`
// hands the plan to a QueryProvider, which decides what to make of it: run it
// in memory, translate it to a storage engine's own query language (see
// std/sql.xi), forward it over the wire (plans serialize — `plan as Json`),
// or reject stages it cannot honor. Results come back as rows (a Json array)
// and the compiler decodes them into the chain's element type — a
// `.collect(p)` on a Query<User> chain yields List<User>, no casts.
//
//     let adults = query.from<User>("users")
//         .filter { it.age >= 18 and it.name.contains("a") }
//         .sortedBy { it.name }
//         .take(10)
//         .collect(db)                    // -> List<User>
//
// Kept un-namespaced (like std/web_core.xi) so user code can
// `implements QueryProvider` and pattern-match the plan types with bare names.
import "std/json.xi"

extern "C" {
    mapper string_len(s: String) -> Integer
    mapper string_char_at(s: String, i: Integer) -> Integer
    mapper string_slice(s: String, a: Integer, b: Integer) -> String
}

// ── the plan: a typed tree ──────────────────────────────────────────
// An expression inside a stage. QField paths are relative to the row; QParam
// values were captured from the enclosing scope when the plan was built.
type QueryExpr =
    | QLit    { value: Json }
    | QField  { path: String }
    | QParam  { value: Json }
    | QBin    { op: String, left: QueryExpr, right: QueryExpr }
    | QUn     { op: String, operand: QueryExpr }
    | QCall   { method: String, recv: QueryExpr, args: List<QueryExpr> }
    | QAgg    { fn: String, operand: QueryExpr }
    | QRecord { names: List<String>, exprs: List<QueryExpr> }

// A whole query: the source name plus its stages, in order. Order is the
// plan's semantics — providers may fold stages but must preserve meaning.
type QueryPlan = { source: String, stages: List<QueryStage> }

type QueryStage =
    | QFilter  { pred: QueryExpr }
    | QProject { expr: QueryExpr }
    | QSortBy  { key: QueryExpr, desc: Bool }
    | QTake    { n: Integer }
    | QDrop    { n: Integer }
    | QConcat  { right: QueryPlan }
    | QJoin    { right: QueryPlan, leftKey: QueryExpr, rightKey: QueryExpr }
    | QGroupBy { key: QueryExpr }

// ── the provider contract ───────────────────────────────────────────
// Receives a reified plan; returns the result rows as a Json array. What
// "run" means is entirely the provider's business. A provider that cannot
// honor a stage or call should fail loudly, naming what it can't translate.
interface QueryProvider {
    producer run(plan: QueryPlan) -> Json
}

// Loading rows into an in-memory provider. MemorySource implements both
// contracts; bind each to it `as singleton` and the two views share one
// instance — load through RowStore, query through QueryProvider.
interface RowStore {
    consumer load(name: String, rows: Json)
}

// ── plan expression evaluation over Json rows ──────────────────────
// These helpers implement plan semantics against in-memory Json values.
// MemorySource uses them; they are also the reference any translating
// provider must agree with.

predicate jsonTruthy(v: Json) {
    let k = json.kind(v)
    if k == 1 { return json.asBool(v) }
    if k == 2 { return json.asNumber(v) != 0.0 }
    if k == 3 { return string_len(json.asString(v)) > 0 }
    if k == 4 or k == 5 { return json.length(v) > 0 }
    return false
}

// three-way compare: numbers numerically, everything else as strings
mapper jsonCmp(a: Json, b: Json) -> Integer {
    if json.kind(a) == 2 and json.kind(b) == 2 {
        let x = json.asNumber(a)
        let y = json.asNumber(b)
        if x < y { return 0 - 1 }
        if x > y { return 1 }
        return 0
    }
    return strCmp(json.asString(a), json.asString(b))
}

mapper strCmp(a: String, b: String) -> Integer {
    let na = string_len(a)
    let nb = string_len(b)
    let n = na
    if nb < n { n = nb }
    let i = 0
    while i < n {
        let ca = string_char_at(a, i)
        let cb = string_char_at(b, i)
        if ca < cb { return 0 - 1 }
        if ca > cb { return 1 }
        i = i + 1
    }
    if na < nb { return 0 - 1 }
    if na > nb { return 1 }
    return 0
}

predicate strContains(s: String, sub: String) {
    let n = string_len(s)
    let m = string_len(sub)
    if m == 0 { return true }
    let i = 0
    while i + m <= n {
        if string_slice(s, i, i + m) == sub { return true }
        i = i + 1
    }
    return false
}

// Walk a dotted field path into a row object.
mapper jsonPath(row: Json, path: String) -> Json {
    if string_len(path) == 0 { return row }
    let cur = row
    let start = 0
    let i = 0
    let n = string_len(path)
    while i <= n {
        let atSep = i == n
        if not atSep { if string_char_at(path, i) == 46 { atSep = true } }
        if atSep {
            cur = json.get(cur, string_slice(path, start, i))
            start = i + 1
        }
        i = i + 1
    }
    return cur
}

mapper evalQBin(op: String, a: Json, b: Json) -> Json {
    if op == "and" { return json.of(jsonTruthy(a) and jsonTruthy(b)) }
    if op == "or"  { return json.of(jsonTruthy(a) or jsonTruthy(b)) }
    if op == "==" { return json.of(jsonCmp(a, b) == 0) }
    if op == "!=" { return json.of(jsonCmp(a, b) != 0) }
    if op == "<"  { return json.of(jsonCmp(a, b) < 0) }
    if op == ">"  { return json.of(jsonCmp(a, b) > 0) }
    if op == "<=" { return json.of(jsonCmp(a, b) <= 0) }
    if op == ">=" { return json.of(jsonCmp(a, b) >= 0) }
    if op == "+" {
        if json.kind(a) == 3 or json.kind(b) == 3 {
            return json.str(json.asString(a) + json.asString(b))
        }
        return json.num(json.asNumber(a) + json.asNumber(b))
    }
    if op == "-" { return json.num(json.asNumber(a) - json.asNumber(b)) }
    if op == "*" { return json.num(json.asNumber(a) * json.asNumber(b)) }
    if op == "/" { return json.num(json.asNumber(a) / json.asNumber(b)) }
    if op == "in" {
        let n = json.length(b)
        let i = 0
        while i < n {
            if jsonCmp(a, json.at(b, i)) == 0 { return json.of(true) }
            i = i + 1
        }
        return json.of(false)
    }
    return json.nul()
}

mapper evalQCall(method: String, recv: Json, args: Json) -> Json {
    let s = json.asString(recv)
    if method == "contains"   { return json.of(strContains(s, json.asString(json.at(args, 0)))) }
    if method == "startsWith" {
        let pre = json.asString(json.at(args, 0))
        let m = string_len(pre)
        if string_len(s) < m { return json.of(false) }
        return json.of(string_slice(s, 0, m) == pre)
    }
    if method == "endsWith" {
        let suf = json.asString(json.at(args, 0))
        let m = string_len(suf)
        let n = string_len(s)
        if n < m { return json.of(false) }
        return json.of(string_slice(s, n - m, n) == suf)
    }
    if method == "length" { return json.int(string_len(s)) }
    if method == "lowercase" or method == "uppercase" {
        let out = ""
        let i = 0
        let n = string_len(s)
        while i < n {
            let c = string_char_at(s, i)
            if method == "lowercase" and c >= 65 and c <= 90 { c = c + 32 }
            if method == "uppercase" and c >= 97 and c <= 122 { c = c - 32 }
            out = out + charStr(c, s, i)
            i = i + 1
        }
        return json.str(out)
    }
    return json.nul()
}

// One character as a string: ASCII letters get the (possibly case-flipped)
// code; anything else passes through unchanged from the source.
mapper charStr(c: Integer, src: String, i: Integer) -> String {
    let orig = string_char_at(src, i)
    if c == orig { return string_slice(src, i, i + 1) }
    // flipped ASCII letter: rebuild from the code point
    return codeToStr(c)
}
mapper codeToStr(c: Integer) -> String {
    let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    let lower = "abcdefghijklmnopqrstuvwxyz"
    if c >= 65 and c <= 90 { return string_slice(upper, c - 65, c - 64) }
    if c >= 97 and c <= 122 { return string_slice(lower, c - 97, c - 96) }
    return ""
}

// Evaluate one plan expression against a row. The reference semantics.
// A grouped row is `{"key": K, "rows": [...]}` — aggregates fold its rows.
mapper evalQ(e: QueryExpr, row: Json) -> Json {
    match e {
        QLit l   -> { return l.value }
        QParam v -> { return v.value }
        QField f -> { return jsonPath(row, f.path) }
        QBin b   -> { return evalQBin(b.op, evalQ(b.left, row), evalQ(b.right, row)) }
        QUn u    -> {
            if u.op == "not" { return json.of(not jsonTruthy(evalQ(u.operand, row))) }
            return json.num(0.0 - json.asNumber(evalQ(u.operand, row)))
        }
        QCall c  -> {
            let args = json.array()
            for a in c.args { args = json.push(args, evalQ(a, row)) }
            return evalQCall(c.method, evalQ(c.recv, row), args)
        }
        QAgg g   -> {
            let members = json.get(row, "rows")
            let n = json.length(members)
            if g.fn == "count" { return json.int(n) }
            let acc = 0.0
            let best = 0.0
            let i = 0
            while i < n {
                let v = json.asNumber(evalQ(g.operand, json.at(members, i)))
                acc = acc + v
                if i == 0 { best = v }
                if g.fn == "min" and v < best { best = v }
                if g.fn == "max" and v > best { best = v }
                i = i + 1
            }
            if g.fn == "sum" { return json.num(acc) }
            if g.fn == "avg" {
                if n == 0 { return json.num(0.0) }
                return json.num(acc / n)
            }
            return json.num(best)
        }
        QRecord r -> {
            let out = json.object()
            let i = 0
            while i < r.names.len() {
                out = json.set(out, r.names.get(i), evalQ(r.exprs.get(i), row))
                i = i + 1
            }
            return out
        }
    }
    return json.nul()
}

// ── the in-memory reference provider ────────────────────────────────
// Interprets plans over rows loaded with `load(name, rows)`. This is the
// semantic yardstick: every translating provider must agree with it, and in
// tests it replaces a real backend with a one-line bind.
class MemorySource implements QueryProvider, RowStore {
    deps {}
    state { names: List<String> = empty List<String>, tables: List<Json> = empty List<Json> }

    consumer load(name: String, rows: Json) {
        this.names.push(name)
        this.tables.push(rows)
    }

    projector tableOf(name: String) -> Json {
        let i = 0
        while i < this.names.len() {
            if this.names.get(i) == name { return this.tables.get(i) }
            i = i + 1
        }
        return json.array()
    }

    producer run(plan: QueryPlan) -> Json {
        let cur = tableOf(plan.source)
        for st in plan.stages { cur = applyStage(st, cur) }
        return cur
    }

    producer applyStage(st: QueryStage, rows: Json) -> Json {
        match st {
            QFilter f -> {
                let out = json.array()
                let n = json.length(rows)
                let i = 0
                while i < n {
                    let r = json.at(rows, i)
                    if jsonTruthy(evalQ(f.pred, r)) { out = json.push(out, r) }
                    i = i + 1
                }
                return out
            }
            QProject pj -> {
                let out = json.array()
                let n = json.length(rows)
                let i = 0
                while i < n {
                    out = json.push(out, evalQ(pj.expr, json.at(rows, i)))
                    i = i + 1
                }
                return out
            }
            QSortBy s -> {
                // selection sort over row indices by the key expression
                let n = json.length(rows)
                let used = empty List<Integer>
                let i = 0
                while i < n { used.push(0)  i = i + 1 }
                let out = json.array()
                let picked = 0
                while picked < n {
                    let best = 0 - 1
                    let j = 0
                    while j < n {
                        if used.get(j) == 0 {
                            if best < 0 { best = j } else {
                                let c = jsonCmp(evalQ(s.key, json.at(rows, j)), evalQ(s.key, json.at(rows, best)))
                                if s.desc { if c > 0 { best = j } } else { if c < 0 { best = j } }
                            }
                        }
                        j = j + 1
                    }
                    used.set(best, 1)
                    out = json.push(out, json.at(rows, best))
                    picked = picked + 1
                }
                return out
            }
            QTake t -> {
                let out = json.array()
                let n = json.length(rows)
                let lim = t.n
                if n < lim { lim = n }
                let i = 0
                while i < lim { out = json.push(out, json.at(rows, i))  i = i + 1 }
                return out
            }
            QDrop d -> {
                let out = json.array()
                let n = json.length(rows)
                let i = d.n
                while i < n { out = json.push(out, json.at(rows, i))  i = i + 1 }
                return out
            }
            QConcat c -> {
                let out = json.array()
                let n = json.length(rows)
                let i = 0
                while i < n { out = json.push(out, json.at(rows, i))  i = i + 1 }
                let more = run(c.right)
                let m = json.length(more)
                let j = 0
                while j < m { out = json.push(out, json.at(more, j))  j = j + 1 }
                return out
            }
            QJoin jn -> {
                // equi-join: pair up rows whose key expressions agree; the
                // joined row is {"first": left, "second": right}.
                let right = run(jn.right)
                let out = json.array()
                let n = json.length(rows)
                let m = json.length(right)
                let i = 0
                while i < n {
                    let l = json.at(rows, i)
                    let lk = evalQ(jn.leftKey, l)
                    let j = 0
                    while j < m {
                        let r = json.at(right, j)
                        if jsonCmp(lk, evalQ(jn.rightKey, r)) == 0 {
                            let pairRow = json.object()
                            pairRow = json.set(pairRow, "first", l)
                            pairRow = json.set(pairRow, "second", r)
                            out = json.push(out, pairRow)
                        }
                        j = j + 1
                    }
                    i = i + 1
                }
                return out
            }
            QGroupBy gb -> {
                // group rows by the key expression: [{"key": K, "rows": [...]}]
                let keys = json.array()
                let out = json.array()
                let n = json.length(rows)
                let i = 0
                while i < n {
                    let r = json.at(rows, i)
                    let k = evalQ(gb.key, r)
                    let found = 0 - 1
                    let g = 0
                    while g < json.length(keys) {
                        if jsonCmp(json.at(keys, g), k) == 0 { found = g }
                        g = g + 1
                    }
                    if found < 0 {
                        keys = json.push(keys, k)
                        let grp = json.object()
                        grp = json.set(grp, "key", k)
                        grp = json.set(grp, "rows", json.push(json.array(), r))
                        out = json.push(out, grp)
                    } else {
                        let grp = json.at(out, found)
                        json.push(json.get(grp, "rows"), r)
                    }
                    i = i + 1
                }
                return out
            }
        }
        return rows
    }
}