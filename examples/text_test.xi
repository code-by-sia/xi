// Unit tests for std/text — run with `xt examples/text_test.xi`.
import "std/text.xi"

test "length and substring" {
    assertEq(text.length("hello"), 5)
    assertEq(text.substring("hello", 1, 4), "ell")
    assert text.isEmpty("")
}

test "char classification (new char helpers)" {
    assert text.isAlpha(text.charAt("a", 0))
    assert text.isAlpha(text.charAt("Z", 0))
    assert text.isDigit(text.charAt("7", 0))
    assert text.isAlnum(text.charAt("q", 0))
    assert text.isSpace(text.charAt(" ", 0))
    assert not text.isAlpha(text.charAt(" ", 0))
    assert not text.isDigit(text.charAt("a", 0))
}

test "indexOfChar and fromCharCode" {
    assertEq(text.indexOfChar("abc", 99), 2)    // 'c' == 99
    assertEq(text.indexOfChar("abc", 122), 0 - 1)  // 'z' absent -> -1
    assertEq(text.fromCharCode(65), "A")
    assertEq(text.fromCharCode(122), "z")
}

test "split and join round-trip" {
    let parts = text.split("a,b,c", ",")
    assertEq(text.join(parts, "-"), "a-b-c")
}

test "predicates and indexOf" {
    assert text.startsWith("hello", "he")
    assert text.endsWith("hello", "lo")
    assert text.contains("hello", "ell")
    assertEq(text.indexOf("hello", "lo"), 3)
    assertEq(text.toUpper("abc"), "ABC")
    assertEq(text.toLower("ABC"), "abc")
}
