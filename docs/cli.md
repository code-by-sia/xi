# CLI & REPL

The toolchain has two commands, installed on your `PATH` (see
[Getting started](getting-started.md)): `xc` compiles, `xi` runs and more.

## `xc` — the compiler

```console
$ xc <source.xi>
```

Pipeline: resolve `import`s → lex → parse → generate C → invoke `cc` →
**native executable**. The binary is written to the output directory `$XC_OUT`
(default `build/`). It's named after the source file, unless the program's
`module` declares an `id` (see [module metadata](dependency-injection.md#module-metadata)),
in which case `id` is used. The intermediate generated C is deleted after a successful
build — set `XC_KEEP_C=1` to keep it for inspection.

```console
$ xc greeting.xi     # -> build/greeting
$ ./build/greeting
Good day, Ada.
```

`xc --all` discovers every **buildable module** under the current directory (a
file with both an `entry` and a `module`) and builds each into its own binary
(named by the module `id`):

```console
$ xc --all
=== xc --all: building ./server.xi ===
xc: built executable build/server
=== xc --all: building ./client.xi ===
xc: built executable build/client
xc --all: built 2 module(s), 0 failed
```

A C compiler (`cc`) must be on your `PATH`, since `xc` builds the native binary by
compiling generated C. `xc version` prints the toolchain version.

### WebAssembly — `xc --target wasm`

Because `xc` compiles through portable C99, the same program can target the web.
`xc --target wasm <source.xi>` routes the generated C + runtime through
[Emscripten](https://emscripten.org) (`emcc`) and emits `build/<name>.{html,js,wasm}`
instead of a native binary:

```console
$ xc --target wasm examples/wasm_demo.xi
xc: built WebAssembly build/wasm_demo.{html,js,wasm}
xc: serve it, e.g.  python3 -m http.server -d build  then open wasm_demo.html
```

Open the generated `.html` in a browser (`stdout`/`stderr` show in the page
console), or run the `.js` under Node. Requires `emcc` on your `PATH`
(`brew install emscripten`). The default target is `native`; pass
`--target native` to be explicit. See [WebAssembly](wasm.md) for what runs in
the browser sandbox and what doesn't.

### Dependencies — `xi install`

A module can list third-party libraries as `dependencies` (URLs to `.tar.gz` /
`.zip` source archives). `xi install [file]` downloads and extracts them into a
`modules/` directory, which `xc` then folds into the build automatically:

```console
$ xi install server.xi        # or: xi install  (every buildable module)
  fetching https://github.com/code-by-sia/xi-sqlite/archive/refs/tags/v0.1.0.tar.gz
xi install: 1/1 fetched into ./modules
$ xc server.xi                # compiles ./modules in, no extra import
```

Needs `curl` (and `unzip` for `.zip`). See
[Multi-file › Dependencies](multi-file.md#dependencies-dependencies--xi-install).

| Environment variable | Meaning | Default |
|----------------------|---------|---------|
| `XC_OUT` | output directory for the built binary | `build` |
| `XC_TARGET` | build target: `native` or `wasm` (same as `--target`) | `native` |
| `XC_KEEP_C` | keep the generated C instead of deleting it | unset |
| `XC_RUNTIME` | C runtime location (set by the installed wrapper) | bundled |
| `XC_STD` | search root for `import "std/..."` (set by the wrapper) | bundled |

> The installed `xc`/`xi` wrappers set `XC_RUNTIME` and `XC_STD` for you, so you
> normally only touch `XC_OUT`.

## `xi` — run tool & REPL

`xi` compiles and runs a file, hosts the REPL, and provides `test` / `skill` /
`update` / `version` subcommands.

### Run a file

```console
$ xi hello.xi
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
xi update: checking code-by-sia/xi ...
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
$ xi test examples/calc_test.xi      # one file
$ xi test --all                      # every *_test.xi under the current dir
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
$ xi
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

## Other `xi` subcommands

| Command | Effect |
|---------|--------|
| `xi test <file.xi>` / `xi test --all` | run a file's `test`s, or every `*_test.xi` in the project ([Testing](testing.md)) |
| `xi skill` | print the AI-agent language guide ([skill](skill.md)) |
| `xi update` | self-update the toolchain to the latest release |
| `xi version` | print the toolchain version |
