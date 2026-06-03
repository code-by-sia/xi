<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/logo-white.svg">
    <img alt="X programming language logo" src="docs/assets/logo.svg" width="140" height="140">
  </picture>
</p>

<h1 align="center">The X Programming Language</h1>

X is a **statically-typed, ahead-of-time compiled** language with **first-class
dependency injection**, **seven function kinds**, and **refined types** that
enforce their constraints. It compiles to native binaries through a C99 backend,
and its compiler is **written in X and self-hosting**.

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

## Why X

- **Dependency injection & IoC are part of the language**, not a framework.
  Implementations are discovered and wired automatically; `bind` is an optional
  override. See [below](#dependency-injection--ioc).
- **Seven function kinds** name a function's role and intent —
  `mapper`, `projector`, `predicate`, `consumer`, `producer`, `reducer`,
  `creator` — and the compiler enforces purity for the pure ones.
- **Decision tables** (`decision` kind) express business rules as
  `when <cond> => <result>` arms — and, being a function kind, they're
  DI-injectable and can call predicates. See
  [decision tables](#decision-tables-dxt).
- **Interrupts** — resumable conditions: a function `signal`s and **suspends**;
  an enclosing `try`/`catch` decides to `recover` (resume) or `skip` (abandon).
  See [`docs/interrupts.md`](docs/interrupts.md).
- **Refined types** carry constraints (`type Age = Number where value >= 0`)
  that are **checked at construction**.
- **Result-based error handling** (`T!`, `ok`/`err`, `?` propagation) — no
  exceptions.
- **`where`-guarded overloading**, `match`, optionals (`T?`), arrays (`T[]`),
  and a `Bytes` type for binary data.
- **Multi-file projects** with `import` and `namespace`.
- **A growing standard library** — math, text, bytes, fs, path, **net (TCP
  sockets)**, **http (HTTP/1.1 client)**, process, time — see
  [`docs/stdlib.md`](docs/stdlib.md).
- **Native, dependency-light output**: X → C99 → a native binary via your `cc`.

Full feature matrix: **[FEATURES.md](FEATURES.md)**. Full guide:
**[docs/](docs/)** (start at [`docs/index.md`](docs/index.md)).

## Quick start

```sh
# Build the compiler. bootstrap.sh downloads the matching released `xc` binary
# (the seed), compiles compiler/xc.x with it, then rebuilds from source with
# itself. Produces ./compiler/xc and ./bin/x (the REPL / run tool).
# Needs curl + a C compiler. Build offline with XC_SEED=/path/to/xc.
./compiler/bootstrap.sh

export XC_RUNTIME="$PWD/runtime"
./compiler/xc examples/greeting.x   # -> build/greeting
./build/greeting

# Or compile-and-run, or start the REPL, with `x`:
export XC="$PWD/compiler/xc"
./bin/x examples/greeting.x          # compile + run
./bin/x                              # interactive REPL
```

## Dependency injection & IoC

DI is built into the language. A class declares what it needs in a `deps { }`
block; at a use site `App.resolve(Interface)` returns a fully-wired instance.
The compiler **discovers implementations automatically** — a `bind` is only
needed to *steer* resolution. When an interface has several implementations, a
dependency disambiguates with a `where` guard, a list type `I[]`, or an `or`
fallback.

```x
interface Logger { consumer log(msg: String) }
class ConsoleLogger implements Logger {
    deps {}
    consumer log(msg: String) { system.stdout.writeln(msg) }
}

interface Calculator { predicate precise() }
class BasicCalc   implements Calculator { deps {} predicate precise() { return false } }
class PreciseCalc implements Calculator { deps {} predicate precise() { return true } }

interface TaxRule { mapper rate() -> Number }
class Vat implements TaxRule { deps {} mapper rate() -> Number { return 20 } }
class Gst implements TaxRule { deps {} mapper rate() -> Number { return 5 } }

interface Repository { mapper name() -> String }
class EmptyRepository implements Repository { deps {} mapper name() -> String { return "empty" } }

interface Service { consumer run() }
class Checkout implements Service {
    deps {
        log:   Logger
        calc:  Calculator where calc.precise()   // pick the impl whose guard holds
        rules: TaxRule[]                          // inject ALL implementations
        repo:  Repository or EmptyRepository      // fall back if none found
    }
    consumer run() {
        log.log("precise? " + calc.precise())
        log.log("rules   = " + rules.len)
        log.log("repo    = " + repo.name())
    }
}

// Functions can declare dependencies too.
mapper { log: Logger } describe(name: String) -> String {
    log.log("describing " + name)
    return "<" + name + ">"
}

async entry main(args: String[]) -> Integer {
    let svc = App.resolve(Service)   // auto-wired; no bind needed
    svc.run()
    system.stdout.writeln(describe("widget"))
    return 0
}

module App {}   // empty: resolution is automatic. Add `bind`s here only to steer,
                // e.g.  bind Logger -> ConsoleLogger as singleton
```

Runnable as [`examples/di_auto.x`](examples/di_auto.x). `singleton` / `transient`
scopes are selected with `bind I -> Impl as singleton`.

## Decision tables (DxT)

The `decision` function kind expresses rules as `when <condition> => <result>`
arms with a final `else`. Conditions are ordinary expressions, so they can call
predicates and use injected dependencies; `hit first` returns the first match.

```x
decision creditTier(score: Number, income: Number) -> String {
    hit first
    when score >= 750                      => "gold"
    when score >= 650 and income >= 50000  => "gold"
    when score >= 650                      => "silver"
    else                                   => "bronze"
}
```

Because it's a function kind, a `decision` can implement an interface method —
making the whole policy DI-injectable:

```x
interface Pricing { decision quote(score: Number, base: Number) -> Number }
class StdPricing implements Pricing {
    deps { risk: RiskModel }
    decision quote(score: Number, base: Number) -> Number {
        hit first
        when risk.risky(score) => base * 2      // condition uses an injected dep
        when score >= 700      => base * 0.9
        else                   => base
    }
}
```

A decision desugars to an `if/return` chain (zero runtime overhead). See
[`docs/decisions.md`](docs/decisions.md) and
[`examples/decision_demo.x`](examples/decision_demo.x).

## A tour of the rest

**Refined types** — constraints enforced when a value is constructed:

```x
type Age    = Number where value >= 0 and value <= 130
type Person = { name: String, age: Age }
predicate isAdult(p: Person) { return p.age >= 18 }   // pure: cannot mutate
```

**Error handling** with `T!`, `ok`/`err`, and `?`:

```x
mapper checkAge(n: Number) -> Age! {
    if n < 0   { return err("age is negative") }
    if n > 130 { return err("age too large") }
    return ok(n)
}
mapper classify(n: Number) -> String! {
    let a = checkAge(n)?              // propagate the Err, else unwrap
    if a < 18 { return ok("minor") }
    return ok("adult")
}
```

**`where`-guarded overloading** — the compiler builds a dispatcher that picks the
first overload whose guard holds:

```x
mapper mapResponse(r: ApiResponse) -> String where r.status == 200 { return "OK: " + r.body }
mapper mapResponse(r: ApiResponse) -> String where r.status >= 500 { return "Server Error" }
mapper mapResponse(r: ApiResponse) -> String { return "Unhandled " + r.status }   // default
```

**`match`**, **multi-file `import` / `namespace`**, the **standard library**, and
more are covered in the [guide](docs/). See [`examples/`](examples/) for runnable
programs (incl. [`fs_demo.x`](examples/fs_demo.x) and a loopback TCP echo in
[`net_demo.x`](examples/net_demo.x)).

## How it compiles

```
source.x (+ imported files)
  ↓ load     resolve `import`s, apply `namespace` prefixing   (compiler/driver.x)
  ↓ lex      tokeniser                                        (compiler/lexer.x)
  ↓ parse    recursive-descent parser                         (compiler/parser.x)
  ↓ codegen  C99: DI wiring, vtables, refined types, overloads, results, match
  ↓ cc       C → native binary (invoked automatically)
```

The compiler is itself an X program (`compiler/*.x`); `selfhost.sh` proves the
fixpoint (successive self-compiles emit byte-identical C). See
[`docs/internals.md`](docs/internals.md).

## Project layout

```
compiler/   the compiler, written in X (lexer, parser, codegen, driver) + xc_helpers.c
            plus bootstrap.sh / fetch-seed.sh / selfhost.sh
runtime/    the C runtime (runtime.h, runtime.c) — the X equivalent of libc/libcore
std/        standard library (math, text, bytes, convert, io, fs, path, net, process, time)
examples/   runnable programs, incl. proj/ (multi-file) and showcase/ (full project)
docs/       MkDocs documentation
editors/    Tree-sitter grammar, Zed extension, Vim plugin
```

## Editor support

A Tree-sitter grammar plus **Zed** and **Vim** integrations live in
[`editors/`](editors/). The grammar parses every `.x` file in this repo.

## License

X is licensed under the **Apache License 2.0** — see [LICENSE](LICENSE) and
[NOTICE](NOTICE) (the same license Kotlin uses). It is provided **"AS IS",
without warranties of any kind, and with no obligation of support**
(Apache-2.0 §7–§8). It's an experimental personal project — issues/PRs are
welcome, but no support or maintenance is guaranteed. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SUPPORT.md](SUPPORT.md).
