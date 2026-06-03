# The X Programming Language

<p align="center">
  <img alt="X logo" src="assets/logo.svg#only-light" width="160" height="160">
  <img alt="X logo" src="assets/logo-white.svg#only-dark" width="160" height="160">
</p>

X is a statically-typed, ahead-of-time compiled language that elevates patterns
usually left to frameworks — **dependency injection**, **function intent**,
**refined types** — into first-class language features. It compiles to native
executables through C.

The compiler is **written in X itself** (`compiler/xc.x`) and is **self-hosting**:
it compiles its own source. The only non-X code is a small C runtime (the
equivalent of a language's libc/libcore).

## Highlights

- **Refined types** — `type Age = Number where value >= 0 and value <= 130`
- **Seven function kinds** — `mapper`, `projector`, `predicate`, `consumer`,
  `producer`, `reducer`, `creator` — intent is syntactic.
- **Dependency injection** in the language — `deps { ... }`, `module { bind ... }`,
  `App.resolve(Interface)`, conditional `when` bindings, `singleton`/`transient`.
- **`where`-guarded overloading** — multiple functions with one name, selected at
  runtime by a guard.
- **Error handling** — `T!` result types, `ok`/`err`, and `?` propagation.
- **`match`** expressions over literals and bindings.
- **Multi-file projects** — `import "file.x"` and `namespace a.b`.
- **Native output** — compiles to a standalone binary via C; no VM, no GC.

## A taste

```x
type Age   = Number where value >= 0 and value <= 130
type User  = { name: String, age: Age }

predicate isAdult(u: User) { return u.age >= 18 }

mapper describe(u: User) -> String {
    return u.name + " (" + u.age + ")"
}

async entry main(args: String[]) -> Integer {
    let u = User { name: "Ada", age: 36 }
    if isAdult(u) { system.stdout.writeln(describe(u)) }
    return 0
}
```

```console
$ ./compiler/xc examples/greeting.x && ./examples/greeting
```

Continue with [Getting started](getting-started.md).
