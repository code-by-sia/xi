// Feature: where-guarded overloads (first matching guard wins; bare = fallback).
type Resp = { status: Integer, body: String }
mapper render(r: Resp) -> String where r.status == 200 { return "OK: " + r.body }
mapper render(r: Resp) -> String where r.status == 404 { return "Not Found" }
mapper render(r: Resp) -> String where r.status >= 500 { return "Server Error" }
mapper render(r: Resp) -> String { return "Other: " + r.status }

test "overload resolution by guard" {
    assertEq(render(Resp { status: 200, body: "hi" }), "OK: hi")
    assertEq(render(Resp { status: 404, body: "" }), "Not Found")
    assertEq(render(Resp { status: 503, body: "" }), "Server Error")
    assertEq(render(Resp { status: 302, body: "" }), "Other: 302")
}
