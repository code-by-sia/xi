// Hardening regressions: untrusted input must be rejected, not corrupt memory.
//
// Each case here mapped to a real defect:
//   - deeply nested JSON recursed until the C stack blew (process crash)
//   - a wide-but-flat document must still parse (the depth guard must not
//     mistake breadth for depth)
//   - repeat()'s size multiply overflowed, under-allocated, and let the copy
//     loop write past the block (that path now aborts, so it is exercised via
//     the safe sizes here plus the overflow guard in the runtime)
import "std/json.xi"
import "std/text.xi"

test "deeply nested JSON is rejected, not fatal" {
    let deep = text.repeat("[", 100000) + text.repeat("]", 100000)
    let v = json.parse(deep)
    assert not json.isValid(v)          // reported as invalid; process survives
}

test "a wide flat document still parses" {
    let wide = "[" + text.repeat("1,", 4999) + "1]"
    let w = json.parse(wide)
    assert json.isValid(w)
    assertEq(json.length(w), 5000)
}

test "nesting within the limit is unaffected" {
    let v = json.parse("{\"a\":{\"b\":{\"c\":[1,2,{\"d\":true}]}}}")
    assert json.isValid(v)
    let c = json.get(json.get(json.get(v, "a"), "b"), "c")
    assertEq(json.asNumber(json.at(c, 0)), 1.0)
}

test "unterminated and malformed JSON is invalid, not a crash" {
    assert not json.isValid(json.parse("{\"a\":"))
    assert not json.isValid(json.parse("[1,2"))
    assert not json.isValid(json.parse("\"unterminated"))
    assert not json.isValid(json.parse("{,}"))
}

test "repeat produces exactly n copies" {
    assertEq(text.repeat("ab", 3), "ababab")
    assertEq(text.repeat("x", 0), "")
    assertEq(text.repeat("x", 0 - 5), "")
    assertEq((text.repeat("ab", 1000)).length, 2000)
}
