// Feature: multiline triple-quoted strings, indent stripping, and `$"..."`
// string interpolation (`${expr}`). Plain `"..."` never interpolates.

test "triple-quoted multiline keeps newlines" {
    let s = """line one
line two"""
    assertEq(s, "line one\nline two")
}

test "triple-quoted strips common indentation + leading newline" {
    let s = """
        alpha
        beta
          deeper"""
    assertEq(s, "alpha\nbeta\n  deeper")
}

test "single-line interpolation of a variable" {
    let name = "John Doe"
    assertEq($"Hello ${name}!", "Hello John Doe!")
}

test "interpolation coerces scalars and evaluates expressions" {
    let age = 36
    assertEq($"age ${age}", "age 36")
    assertEq($"sum ${age + 4}", "sum 40")
}

test "interpolation with multiple holes" {
    let a = "x"
    let b = "y"
    assertEq($"${a}-${b}-${a}", "x-y-x")
}

test "triple-quoted interpolation strips indent and fills holes" {
    let name = "John Doe"
    let age = 36
    let s = $"""
        Name: ${name}
        Age:  ${age}"""
    assertEq(s, "Name: John Doe\nAge:  36")
}

test "plain string never interpolates (bash-safe)" {
    assertEq("shell ${HOME}/bin", "shell ${HOME}/bin")
}
