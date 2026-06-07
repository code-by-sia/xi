# CLI & REPL

## `xc` — the compiler

```console
$ ./compiler/xc <source.xi>
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

### AI agent skill

`xi skill` downloads the latest **[Xi agent guide](skill.md)** (a single markdown
file that teaches an AI how to write Xi) and writes it locally:

```console
$ xi skill                 # writes ./skill.md
xi skill: downloading the Xi agent guide ...
xi skill: wrote skill.md — give this file to your AI agent so it can write Xi.

$ xi skill docs/XI.md      # or pick the output path
```

Hand the resulting file to your coding agent (e.g. as a project skill / context
file). Requires `curl`; override the source with `XI_SKILL_URL` (or
`XI_SKILL_REPO` / `XI_SKILL_REF`).

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
