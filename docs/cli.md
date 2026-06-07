# CLI & REPL

## `xc` — the compiler

```console
$ ./compiler/xc <source.xi>
```

Pipeline: resolve `import`s → lex → parse → generate C → invoke `cc` →
**native executable**. The binary is written to the output directory `$XC_OUT`
(default `build/`). It's named after the source file, unless the program's
`module` declares an `id` (see below), in which case `id` is used. The intermediate `<name>.gen.c` is generated there and then
**deleted after a successful build** — set `XC_KEEP_C=1` to keep it (e.g. to
inspect the generated C or diff the self-hosting output).

| Environment variable | Meaning | Default |
|----------------------|---------|---------|
| `XC_RUNTIME` | directory containing `runtime.h` / `runtime.c` | `runtime` |
| `XC_OUT` | output directory for the built binary (and the transient generated C) | `build` |
| `XC_KEEP_C` | keep the generated `<name>.gen.c` instead of deleting it | unset |
| `XC_STD` | search root for `import "std/..."` | `.` |
| `XC_HELPERS` | C file appended to the output (only needed when compiling the compiler itself) | unset |

```console
$ export XC_RUNTIME="$PWD/runtime"
$ ./compiler/xc examples/greeting.xi     # -> build/greeting
$ ./build/greeting
Good day, Ada.
```

## `x` — run tool & REPL

`x` is a native binary (compiled from `compiler/repl.xi`). It finds the compiler
via the `XC` env var (default `compiler/xc`) and the runtime via `XC_RUNTIME`.

### Run a file

```console
$ ./bin/xi examples/hello.xi
Hello World!
```

This compiles the file and runs the resulting binary.

### Version

```console
$ xi version          # also: xi --version, xi -v
xi 0.0.50
```

### Self-update

`xi update` downloads the latest release bundle for your platform from GitHub and
replaces the installed `xc`/`xi` binaries, `runtime/`, and `std/` **in place** —
no reinstall needed.

```console
$ xi update
xi update: checking code-by-sia/x ...
current: 0.0.49   latest: 0.0.50
downloading xi-v0.0.50-macos-arm64.tar.gz ...
xi updated: 0.0.49 -> 0.0.50
```

It no-ops with "already up to date" when you're on the latest version. Notes:

- Works on an **installed release bundle** (the `bin/` + `libexec/` layout); run
  it from a source checkout and it reports that it can't find an install root.
- Needs write access to the install directory — use `sudo xi update` if you
  installed under a system path.
- Requires `curl` and `tar` on `PATH`. Override the source repo with
  `XI_UPDATE_REPO=owner/name`.

### Run tests

`xi test <file.xi>` compiles in test mode and runs the file's `test` cases,
printing `ok`/`not ok` per case, a summary, and a nonzero exit code if any failed.
See [Testing](testing.md).

```console
$ xi test examples/calc_test.xi
ok - addition
...
3 tests, 3 passed, 0 failed
```

### AI agent skill

`xi skill` fetches the latest **[Xi agent guide](skill.md)** (a single markdown
file that teaches an AI how to write Xi) and **prints it to stdout** — pipe it to
a file or straight to your coding agent:

```console
$ xi skill > SKILL.md        # save it
$ xi skill | pbcopy          # or copy it to hand to an agent
```

Status/errors go to stderr, so stdout is clean markdown. Requires `curl`;
override the source with `XI_SKILL_URL` (or `XI_SKILL_REPO` / `XI_SKILL_REF`).

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
