# Getting started

## Requirements

- A C compiler (`cc` — clang or gcc).
- `curl` and a POSIX shell.
- Network access to download the bootstrap seed (or an existing `xc` via `XC_SEED`).

Supported platforms: **Linux** (x86_64, arm64) and **macOS** (arm64, x86_64).

## Windows

There is no native Windows build yet — the runtime uses POSIX APIs (sockets,
directories, processes). On Windows, use **WSL2**: install a Linux distribution,
then follow the Linux instructions unchanged (download the `linux-x86_64`
release or build from source inside WSL). A native Windows port is tracked as
future work.

## Build the compiler from source

The compiler is self-hosting. `bootstrap.sh` downloads the released `xc` binary
for your platform (the seed), compiles `compiler/xc.x` with it, then rebuilds the
result from source with itself — so the compiler you get is built from the
current source, not the download:

```console
$ ./compiler/bootstrap.sh
==> [seed] fetching a released compiler to bootstrap from ...
==> [stage1] seed compiler builds xc from compiler/xc.x ...
==> [stage2] xc rebuilds itself from compiler/xc.x ...
==> Building the REPL / run tool 'x' from compiler/repl.x ...
Bootstrap complete. The compiler is built from current X source.
```

Pin the seed with `XC_BOOTSTRAP_VERSION=v0.0.0`, or build offline by pointing
`XC_SEED` at an existing `xc` binary.

This produces:

- `compiler/xc` — the compiler.
- `x` — the REPL / run tool.

## Hello, world

```x title="hello.x"
interface Printer { consumer print(msg: String) }

class ConsolePrinter implements Printer {
    deps {}
    consumer print(msg: String) { system.stdout.writeln(msg) }
}

module HelloApp { bind Printer -> ConsolePrinter as singleton }

async entry main(args: String[]) -> Integer {
    let printer = HelloApp.resolve(Printer)
    printer.print("Hello, World!")
    return 0
}
```

Compile and run:

```console
$ export XC_RUNTIME="$PWD/runtime"
$ ./compiler/xc hello.x        # writes build/hello (a native binary)
$ ./build/hello
Hello, World!
```

Or do both at once with the `x` tool:

```console
$ ./bin/x hello.x
Hello, World!
```

!!! note "XC_RUNTIME"
    The compiler needs to know where the C runtime lives so it can invoke `cc`.
    It defaults to `runtime` (relative to the current directory); set
    `XC_RUNTIME` to an absolute path if you run from elsewhere.

## Verify self-hosting

```console
$ ./compiler/selfhost.sh
    ✓ byte-identical (4582 lines) — stable self-hosting fixpoint
SELF-HOSTING VERIFIED — bootstraps from C source.
```

Next: the [CLI & REPL](cli.md), or the [Language guide](language-guide.md).
