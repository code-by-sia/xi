---
title: The Ξ Programming Language
hide_title: true
sidebar_label: Overview
slug: /
---

<div class="hero-x">
  <img class="hero-x__logo hero-x__logo--light" src="/x/img/logo.svg" alt="Xi logo" width="88" height="88" />
  <img class="hero-x__logo hero-x__logo--dark" src="/x/img/logo-white.svg" alt="Xi logo" width="88" height="88" />
  <h1 class="hero-x__title">The Ξ (Xi) Programming Language</h1>
  <p class="hero-x__tagline">
    A statically-typed, ahead-of-time compiled language that makes
    <strong>dependency injection</strong>, <strong>function intent</strong>, and
    <strong>refined types</strong> first-class — compiled to native binaries
    through C, and self-hosting.
  </p>
  <p class="hero-x__cta">
    <a class="button button--primary button--lg" href="/x/getting-started">Get started →</a>
    <a class="button button--secondary button--lg" href="https://github.com/code-by-sia/x">GitHub</a>
  </p>
</div>

Xi is **self-hosting** — its compiler is written in Xi and compiles its own source
to a byte-identical fixpoint. The only non-Xi code is a small C runtime (the
equivalent of a language's libc/libcore). You don't need any of that to write
Xi — [install the toolchain](getting-started.md) and go.

## Highlights

- **Refined types** — `type Age = Number where value >= 0 and value <= 130`,
  checked at construction.
- **Seven function kinds** — `mapper`, `projector`, `predicate`, `consumer`,
  `producer`, `reducer`, `creator`: intent is syntactic.
- **Dependency injection** in the language — `deps { ... }`, `module { bind ... }`,
  `App.resolve(Interface)`, conditional `when` bindings, `singleton`/`transient`.
- **`where`-guarded overloading** — multiple functions with one name, selected by
  a guard.
- **Decision tables, interrupts, atoms, machines & events** — business rules,
  resumable conditions, active-state stores, finite state machines, and
  publish/subscribe with the `listener` kind, all as language features.
- **Error handling** — `T!` result types, `ok`/`err`, and `?` propagation.
- **Serialization** — a built-in [`std/json`](serialization.md) library.
- **Native output** — compiles to a standalone binary via C; no VM, no GC.

## A taste

```x
import "std/log.xi"

type Age   = Number where value >= 0 and value <= 130
type User  = { name: String, age: Age }

predicate isAdult(u: User) { return u.age >= 18 }

mapper describe(u: User) -> String {
    return u.name + " (" + u.age + ")"
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let u = User { name: "Ada", age: 36 }
    if isAdult(u) { logger.info(describe(u)) }
    return 0
}
```

```console
$ xc greeting.xi && ./build/greeting
```

Ready? Head to [Getting started](getting-started.md).
