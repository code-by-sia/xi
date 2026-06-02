# Getting started

## Requirements

- A C compiler (`cc` — clang or gcc).
- A POSIX shell.

That's it.

## Build the compiler from source

The compiler is self-hosting, so it ships a generated C seed
(`compiler/xc.stage0.c`) that `cc` turns into a working compiler, which then
rebuilds itself from `compiler/xc.x`:

```console
$ ./compiler/bootstrap.sh
==> [stage0] Building xc from compiler/xc.stage0.c with cc ...
==> [stage1] Rebuilding xc from compiler/xc.x using the stage0 compiler ...
==> Building the REPL / run tool 'x' from compiler/repl.x ...
Bootstrap complete. The compiler is built entirely from X + C.
```

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
