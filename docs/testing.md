# Testing

Xi has built-in tests and assertions — no framework to install. Write `test`
cases, run them with `xi test`.

## Writing tests

A `test "name" { … }` case asserts with `assert <expr>`:

```x
mapper add(a: Integer, b: Integer) -> Integer { return a + b }

test "addition" {
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
}
```

Run them:

```console
$ xi test examples/calc_test.xi
ok - addition
ok - multiplication
not ok - subtraction
    assert sub(5, 1) == 3  (calc_test.xi:14)

3 tests, 2 passed, 1 failed
```

`xi test` compiles the file in **test mode**, runs every `test`, and exits
nonzero if any failed (so it drops straight into CI). The program's own `entry`
is ignored in test mode, and `test` cases are **stripped from normal `xc`
builds**.

There is also a standalone **`xt`** binary (the `Test` module) with the same
engine and flags — `xt <file_test.xi> [--filter <substr>]` and
`xt --all` — for running tests without the rest of the `xi` tool. See
[CLI › `xt`](cli.md#xt--test-runner).

## `assert`

`assert <bool-expr>` is a general statement — it works anywhere, not just in
tests:

- **Inside a `test`:** a failed assert reports the expression text + `file:line`,
  marks the test failed, and **aborts just that test** — the remaining tests
  still run.
- **In a normal program:** a failed assert prints `assertion failed: … (file:line)`
  and aborts the process. Handy as a precondition/invariant check.

```x
assert balance >= 0          // invariant in normal code: aborts if violated
```

A failure message can be attached with `: "…"`:

```x
assert balance >= 0 : "balance must never go negative"
```

## Value-showing assertions

`assert a == b` only reports the *expression text*. The `assert*` helpers report
the **actual values**, which is what you usually want from a failing test:

```x
assertEq(actual, expected)   // fail: "expected <expected>, got <actual>"
assertNe(a, b)               // fail: "both values were <a>"
assertClose(a, b, 0.0001)    // numeric equality within a tolerance (floats)
assertOk(result)             // a Result `T!` is ok  (fail prints the Err message)
assertErr(result)            // a Result `T!` is err
```

```x
test "math" {
    assertEq(add(2, 2), 5)              // not ok: assertEq: expected 5, got 4
    assertClose(0.1 + 0.2, 0.3, 1e-9)  // ok — no spurious float failure
}
test "parsing" {
    assertErr(parseAge(""))            // assert the failure path
    assertOk(parseAge("30"))
}
```

`assertEq`/`assertNe` compare primitives and `String`s (Strings by content).
`assertOk`/`assertErr` take a `T!` [result](error-handling.md) and report its
`Err` message on failure — so you can finally test error paths directly.

## Running a subset — `--filter`

```console
$ xi test users_test.xi --filter "login"     # only tests whose name contains "login"
```

`--filter <substr>` runs only the tests whose name contains the substring (it
sets `XC_TEST_FILTER` for the test binary; the summary counts only what ran).

## Injecting test doubles — `module Test`

Tests get dependencies injected with the same `(dep: I)` form as `entry` and
functions. A `module Test { bind … }` supplies test doubles; it **layers over
`module App`** (Test wins, App fills the rest) and is **ignored in normal
builds**:

```x
interface Clock { mapper now() -> Integer }
class RealClock implements Clock { deps {} mapper now() -> Integer { return systemNow() } }
class FakeClock implements Clock { deps {} mapper now() -> Integer { return 42 } }

test "uses the fake clock" (clock: Clock) {
    assert clock.now() == 42
}

module Test { bind Clock -> FakeClock }   // only applies under `xi test`
module App  { bind Clock -> RealClock }
```

`App.resolve(Clock)` inside a test returns the `module Test` binding too.

## Conventions

- Put tests in `*_test.xi` files (the toolchain compiles those via `xi test`, not
  as normal programs). You can also keep tests beside code in any file.
- One assertion per logical fact reads best; the first failing assert ends that
  test.

## What's planned

`before`/`after` fixtures, table/parameterized tests, per-test timeouts (relevant
for `async`/threaded code), and parallel runs are future additions; the core
above — value-showing assertions, messages, error-path assertions, `module Test`
doubles, and `--filter` — is stable.
