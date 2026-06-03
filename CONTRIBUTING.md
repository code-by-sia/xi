# Contributing to X

Thanks for your interest! X is an experimental, self-hosting language. This
guide covers how to build it, what to check before opening a pull request, and
how the project is laid out.

> X is provided **as is**, with no warranty and no obligation of support
> (see [SUPPORT.md](SUPPORT.md) and the [LICENSE](LICENSE)). Contributions are
> welcome but reviewed on a best-effort basis.

## Prerequisites

- A C compiler (`cc` — clang or gcc)
- `curl` and a POSIX shell
- Network access (to download the bootstrap seed), or an existing `xc` binary

## Build

The compiler is self-hosting. `bootstrap.sh` downloads the released `xc` for your
platform, compiles `compiler/xc.x` with it, then rebuilds the result from source
with itself:

```sh
./compiler/bootstrap.sh        # -> ./compiler/xc and ./bin/x
```

To build offline, point `XC_SEED` at any working `xc`:

```sh
XC_SEED=/path/to/xc ./compiler/bootstrap.sh
```

## Before you open a PR

1. **Self-hosting fixpoint must hold.** Any change to `compiler/*.x`,
   `compiler/xc_helpers.c`, or `runtime/` must still produce a byte-identical
   fixpoint:

   ```sh
   ./compiler/selfhost.sh
   ```

2. **Examples must compile and run.** This is what CI checks:

   ```sh
   export XC_RUNTIME="$PWD/runtime"
   for f in examples/*.x examples/proj/main.x examples/showcase/main.x; do
       ./compiler/xc "$f"
   done
   ```

3. **Add coverage for new features.** A new language feature should come with a
   small example under `examples/` (it will be compiled and run by CI).

4. **Update docs** in `docs/` and the `README.md` feature table when behaviour
   changes.

There is no checked-in C seed to regenerate — `bootstrap.sh` always rebuilds
from source, so you never commit generated C.

## Project layout

```
compiler/   the compiler, written in X (lexer, parser, codegen, driver) + xc_helpers.c
runtime/    the C runtime (runtime.h, runtime.c)
std/        the standard library (X modules wrapping the runtime)
examples/   programs exercised by CI
docs/       MkDocs documentation
editors/    tree-sitter grammar, Zed and Vim integrations
scripts/    release packaging
```

See `docs/internals.md` for the pipeline and self-hosting details.

## Commits and pull requests

- Keep each commit a single logical change with a clear message.
- Branch from `main`; CI (build + self-host fixpoint + examples) runs on every PR.
- By contributing you agree your work is licensed under the project's
  [Apache-2.0](LICENSE) license.

## Reporting bugs / proposing features

Open an issue using the templates. For security issues, follow
[SECURITY.md](SECURITY.md) instead of filing a public issue.
