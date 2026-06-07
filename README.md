<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo-white.svg">
    <img alt="Xi programming language logo" src="docs/assets/logo.svg" width="140" height="140">
  </picture>
</p>

<h1 align="center">The Ξ (Xi) Programming Language</h1>

Xi is a **statically-typed, ahead-of-time compiled** language with **first-class
dependency injection**, **seven function kinds**, and **refined types** that
enforce their constraints. It compiles to native binaries through a C99 backend,
and its compiler is **written in Xi and self-hosting**.

```x
interface Greeter { mapper greet(name: String) -> String }

class Friendly implements Greeter {
    deps {}
    mapper greet(name: String) -> String {
        return "Hello, " + name + "!"
    }
}

async entry main(args: String[]) -> Integer {
    let g = App.resolve(Greeter)          // auto-wired — no manual construction
    system.stdout.writeln(g.greet("Ada"))
    return 0
}

module App {}                             // resolution is automatic
```

## Why Xi

- **Dependency injection & IoC are part of the language**, not a framework.
  Implementations are discovered and wired automatically; `bind` is an optional
  override.
- **Eight function kinds** name a function's role and intent —
  `mapper`, `projector`, `predicate`, `consumer`, `producer`, `reducer`,
  `creator`, `action` — and the compiler enforces purity for the pure ones.
- **Decision tables** (`decision` kind) express business rules as
  `when <cond> => <result>` arms (or a tabular `in`/`out` grid) — and, being a
  function kind, they're DI-injectable and can call predicates.
- **Interrupts** — resumable conditions: a function `signal`s and **suspends**;
  an enclosing `try`/`catch` decides to `recover` (resume) or `skip` (abandon).
  See [Interrupts](https://code-by-sia.github.io/x/interrupts).
- **Atoms** — active-state stores: an immutable `state` changed only via
  `transition` reducers (Redux-style). See [Atoms](https://code-by-sia.github.io/x/atoms).
- **Machines** — finite state machines as immutable values: named `states`,
  machine-wide `data`, transitions with parameters, `where` guards and `update`
  clauses, `.can(...)`, and illegal moves that raise the resumable
  `IllegalTransition` interrupt. See [Machines](https://code-by-sia.github.io/x/machines).
- **Events** — built-in typed publish/subscribe. Producers `publish(topic, dto)`
  any DTO; the `listener` kind subscribes to a topic and receives the **typed**
  value (no JSON). The default transport queues in memory with zero serialization;
  bind your own `PublisherService`/`ConsumerService` to go external — producers and
  listeners are unchanged. Deliver synchronously (`Events.run`) or on a worker
  thread (`Events.runAsync`). See [Events](https://code-by-sia.github.io/x/events).
- **Web framework** — implement `WebRequestHandler` and route by overloading
  `action handle(req, res)` with `where` guards; `res.send(dto)` / `req.parse(T)`
  auto-(de)serialize via a pluggable `WebTransport` (JSON by default). No manual
  JSON. Plain HTTP by default; opt-in **HTTPS** (`web.serveTLS`, `XC_TLS=1`) and
  **HTTP/2** (`web.serveHttp2`, `XC_HTTP2=1`). See [Web](https://code-by-sia.github.io/x/web).
- **Share-nothing threading** — `parallel { }` blocks run on OS threads and yield
  a `Thread` handle (`stop`/`wait`/`running`); threads talk only over thread-safe
  channels. See [Threading](https://code-by-sia.github.io/x/threading).
- **Refined types** carry constraints (`type Age = Number where value >= 0`)
  that are **checked at construction**.
- **Sum / algebraic types** (`type Shape = | Circle { r: Number } | Empty`) with
  payload-binding `match` — lowered to tagged unions.
- **Result-based error handling** (`T!`, `ok`/`err`, `?` propagation) — no
  exceptions.
- **`where`-guarded overloading**, `match`, optionals (`T?`), arrays (`T[]`),
  and a `Bytes` type for binary data.
- **Multi-file projects** with `import` and `namespace`.
- **A growing standard library** — math, text, bytes, convert, **serialization
  (json / yaml / xml)**, **crypto (SHA/HMAC/base64/CSPRNG)**, fs, path,
  **net (TCP sockets)**, **http (HTTP/1.1 client)**, **web (REST framework)**,
  **thread (share-nothing threads + channels)**, process, time — see
  [the standard library](https://code-by-sia.github.io/x/stdlib) and
  [serialization](https://code-by-sia.github.io/x/serialization).
- **Native, dependency-light output**: Xi → C99 → a native binary via your `cc`.

Full feature matrix: **[FEATURES.md](FEATURES.md)**. Full guide:
**[code-by-sia.github.io/x](https://code-by-sia.github.io/x/)**.

## Quick start

Download a prebuilt toolchain for your platform from the
**[releases page](https://github.com/code-by-sia/x/releases)**, unpack it, and
put its `bin/` on your `PATH`:

```sh
# grab the asset for your platform, e.g. xi-<version>-macos-arm64.tar.gz
tar -xzf xi-<version>-<os>-<arch>.tar.gz
export PATH="$PWD/xi-<version>-<os>-<arch>/bin:$PATH"

xc hello.xi        # compile  -> build/hello
xi hello.xi        # compile and run
xi                 # interactive REPL
xi version         # print the toolchain version
xi update          # self-update to the latest release
```

Once installed, `xi update` upgrades the toolchain in place (downloads the latest
release for your platform and replaces the binaries, runtime, and stdlib).

The bundle ships the `xc` compiler, the `xi` REPL / run tool, the runtime, and
the standard library; the `bin/` wrappers set `XC_RUNTIME` / `XC_STD` for you.
You need a C compiler (`cc` / `clang` / `gcc`) on `PATH`, since `xc` produces
native binaries via C. (To build from source instead, run
`./compiler/bootstrap.sh` — see
[github.com/code-by-sia/x](https://github.com/code-by-sia/x).)

Runs on **Linux** (x86_64/arm64) and **macOS** (arm64/x86_64). On **Windows**,
use **WSL2** and follow the Linux steps, or run the toolchain in **Docker** (no
native Windows build yet):

```powershell
docker build -t xi .
docker run --rm -v "${PWD}:/work" xi xi hello.xi   # compile + run
docker run --rm -v "${PWD}:/work" xi xc hello.xi   # compile -> build/hello
docker run --rm -it -v "${PWD}:/work" xi xi        # REPL
```

The image downloads a published release; pin one with
`--build-arg XI_VERSION=v0.0.14`. See the [`Dockerfile`](Dockerfile).

## Documentation

Full documentation — the language guide, dependency injection & IoC, decision
tables, interrupts, atoms, state machines, events, serialization, the standard
library, and the compiler internals — lives in the repository at
**[github.com/code-by-sia/x](https://github.com/code-by-sia/x)**
(rendered at [code-by-sia.github.io/x](https://code-by-sia.github.io/x/)).

## Project layout

```
compiler/   the compiler, written in Xi (lexer, parser, codegen, driver) + xc_helpers.c
            plus bootstrap.sh / fetch-seed.sh / selfhost.sh
runtime/    the C runtime (runtime.h, runtime.c) — the Xi equivalent of libc/libcore
std/        standard library (math, text, bytes, convert, json, yaml, xml, crypto, events, web, io, fs, path, net, http, process, time)
examples/   runnable programs, incl. proj/ (multi-file) and showcase/ (full project)
docs/       documentation (Docusaurus site under website/)
editors/    Tree-sitter grammar, Zed extension, Vim plugin
```

## Editor support

A Tree-sitter grammar plus **Zed** and **Vim** integrations live in
[`editors/`](editors/). The grammar parses every `.xi` file in this repo.

## License

Xi is licensed under the **Apache License 2.0** — see [LICENSE](LICENSE) and
[NOTICE](NOTICE). It is provided **"AS IS",
without warranties of any kind, and with no obligation of support**
(Apache-2.0 §7–§8). It's an experimental personal project — issues/PRs are
welcome, but no support or maintenance is guaranteed. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SUPPORT.md](SUPPORT.md).
