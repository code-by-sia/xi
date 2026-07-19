// Values stored into long-lived state must not point into a dying arena.
//
// A request/thread arena is destroyed when its work finishes. A value allocated
// there and stored into a singleton's `state` would leave a dangling pointer —
// which reads back as garbage rather than failing loudly. Codegen copies such a
// value out of the arena on the way in.
//
// These cases run without an arena (a test binary), so they assert the *value*
// semantics the promotion must preserve: a stored value stays intact and
// independent. The dangling case itself is exercised under AddressSanitizer
// against a live server, where it previously reported heap-use-after-free.
import "std/json.xi"
import "std/text.xi"

interface Store {
    consumer put(s: String)
    consumer putJson(j: Json)
    producer joined() -> String
    producer firstName() -> String
    projector count() -> Integer
}

class MemStore implements Store {
    deps {}
    state { items: List<String> = empty List<String>, rows: List<Json> = empty List<Json> }

    consumer put(s: String) { this.items.push(s) }
    consumer putJson(j: Json) { this.rows.push(j) }
    projector count() -> Integer => this.items.len()

    producer joined() -> String {
        let out = ""
        for i in this.items { out = out + "[" + i + "]" }
        return out
    }
    producer firstName() -> String {
        if this.rows.len() == 0 { return "" }
        return json.getString(this.rows.get(0), "name")
    }
}

module App { id = "promotion_test" }

test "strings stored into state survive and keep their value" (st: Store as singleton) {
    // built at runtime (not a literal), the shape that would be arena-allocated
    st.put("v-" + text.repeat("a", 3))
    st.put("v-" + text.repeat("b", 2))
    assertEq(st.count(), 2)
    assertEq(st.joined(), "[v-aaa][v-bb]")
}

test "a stored string is independent of later mutation" (st: Store as singleton) {
    // each test body gets its own store, so assert only on what this test stores
    let base = "x"
    let s = base + "-one"
    st.put(s)
    let s2 = s + "-two"                  // building a new value must not disturb the stored one
    assertEq(st.joined(), "[x-one]")
    assertEq(s2, "x-one-two")
}

test "json stored into state keeps its contents" (st: Store as singleton) {
    let o = json.object()
    o = json.set(o, "name", json.str("n-" + text.repeat("z", 2)))
    st.putJson(o)
    assertEq(st.firstName(), "n-zz")
}

test "a deep json tree survives storage" (st: Store as singleton) {
    let inner = json.object()
    inner = json.set(inner, "name", json.str("deep"))
    let arr = json.array()
    arr = json.push(arr, inner)
    let outer = json.object()
    outer = json.set(outer, "name", json.str("outer"))
    outer = json.set(outer, "items", arr)
    st.putJson(outer)
    // the nested node must have come along intact, not just the root
    let stored = json.get(json.at(json.get(outer, "items"), 0), "name")
    assertEq(json.asString(stored), "deep")
}
