# CLI & REPL

## `xc` — the compiler

```console
$ ./compiler/xc <source.x>
```

Pipeline: resolve `import`s → lex → parse → generate C → invoke `cc` →
**native executable**. Build artifacts (the executable and the generated
`<name>.gen.c`) are written to the output directory `$XC_OUT` (default `build/`),
keeping source trees clean.

| Environment variable | Meaning | Default |
|----------------------|---------|---------|
| `XC_RUNTIME` | directory containing `runtime.h` / `runtime.c` | `runtime` |
| `XC_OUT` | output directory for built binaries + generated C | `build` |
| `XC_STD` | search root for `import "std/..."` | `.` |
| `XC_HELPERS` | C file appended to the output (only needed when compiling the compiler itself) | unset |

```console
$ export XC_RUNTIME="$PWD/runtime"
$ ./compiler/xc examples/greeting.x     # -> build/greeting
$ ./build/greeting
Good day, Ada.
```

## `x` — run tool & REPL

`x` is a native binary (compiled from `compiler/repl.x`). It finds the compiler
via the `XC` env var (default `compiler/xc`) and the runtime via `XC_RUNTIME`.

### Run a file

```console
$ ./bin/xi examples/hello.x
Hello, World!
```

This compiles the file and runs the resulting binary.

### Interactive REPL

```console
$ ./bin/xi
Xi REPL — :help for commands, :quit to exit
x> let n = 21
x> print("n = " + n)
n = 21
x> mapper dbl(x: Number) -> Number { return x * 2 }
(defined)
x> print("double = " + dbl(n))
double = 42
x> :quit
bye
```

The REPL is a **compile-and-run loop**:

- **Declarations** (`type`, `class`, `mapper`, `interface`, …) accumulate across
  the session and persist.
- **Statements** are appended to the session and the whole program is recompiled
  and re-run; only the *new* output is shown.
- Use `print(x)` to display a value (`print` takes a `String`; build one with
  `+`, e.g. `print("x = " + x)`).

| Command | Effect |
|---------|--------|
| `:help`  | show commands |
| `:reset` | clear the session |
| `:dump`  | print the accumulated program |
| `:quit`  | exit |

!!! tip "Putting `x` on your PATH"
    `x` uses relative defaults (`compiler/xc`, `runtime`), so it's simplest to
    run it from the project root. To install globally, copy `x`, `compiler/xc`,
    and `runtime/` somewhere and set `XC` and `XC_RUNTIME` to absolute paths.
