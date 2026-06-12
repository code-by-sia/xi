# Getting started

## Install

### Homebrew (macOS + Linux)

```sh
brew install code-by-sia/x/xi
brew upgrade xi        # later, to update
```

### Tarball (any supported platform)

Download the toolchain for your platform from the
**[releases page](https://github.com/code-by-sia/x/releases)**, unpack it, and put
its `bin/` on your `PATH`:

```sh
# grab the asset for your platform, e.g. xi-<version>-macos-arm64.tar.gz
tar -xzf xi-<version>-<os>-<arch>.tar.gz
export PATH="$PWD/xi-<version>-<os>-<arch>/bin:$PATH"
```

Either way you get two commands — `xc` (compiler) and `xi` (run tool + REPL).
Tarball installs upgrade in place with `xi update`; Homebrew installs upgrade
with `brew upgrade xi`.

**Requirements:** a C compiler (`cc` — clang or gcc) on your `PATH`, since `xc`
produces a native binary by compiling generated C. Supported platforms:
**Linux** (x86_64, arm64) and **macOS** (arm64, x86_64).

### Windows

No native Windows build yet (the runtime uses POSIX APIs). Use **WSL2** (install a
Linux distro and follow the Linux steps), or **Docker**:

```powershell
docker build -t xi .   # from a clone of the repo
docker run --rm -v "${PWD}:/work" xi xi hello.xi   # compile + run
docker run --rm -it -v "${PWD}:/work" xi xi        # REPL
```

## Hello, world

```x title="hello.xi"
import "std/log.xi"

async entry (logger: Logger) main(args: String[]) {
    logger.info("Hello World!")
}

module App {}
```

`(logger: Logger)` on the entry asks for a `Logger` by interface; the compiler
injects the standard `ConsoleLogger` — no globals, no setup. (Bind your own
`Logger` later and `main` doesn't change.) See
[Dependency injection](dependency-injection.md).

`entry` always returns `Integer`, so the `-> Integer` is optional and a body
without a `return` exits `0` — write `-> Integer` and `return <code>` only when
you want a non-zero exit code. (An unhandled interrupt that reaches `main`
aborts with a non-zero status.)

Compile to a native binary, then run it:

```console
$ xc hello.xi        # writes build/hello
$ ./build/hello
Hello World!
```

Or compile and run in one step with `xi`:

```console
$ xi hello.xi
Hello World!
```

## Try the REPL

```console
$ xi
Xi REPL — :help for commands, :quit to exit
x> let n = 21
x> print("double = " + n * 2)
double = 42
x> :quit
```

## Next steps

- The [Language guide](language-guide.md) — types, functions, control flow.
- [Dependency injection](dependency-injection.md), [Testing](testing.md), and the
  [standard library](stdlib.md).
- [CLI & REPL](cli.md) for `xc`/`xi` options, `xi test`, `xi skill`, and `xi update`.
- `xi skill > SKILL.md` produces a single-file language guide for AI coding agents.
- A full real-world app: **[eXstream](https://github.com/code-by-sia/eXstream)**, a
  music-streaming service with Xi microservices, a React front end, and Docker.

> Building the compiler from source (it's self-hosting) is covered in
> [Compiler internals](internals.md) and the repository `README` — you don't need
> that to write Xi.
