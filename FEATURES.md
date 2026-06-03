# X — language feature matrix

Status of language and toolchain features. See [`docs/`](docs/) for the full
guide and [`README.md`](README.md) for a tour with examples.

## Type system

| Feature | Status |
|---------|--------|
| Refined types (`type Age = Number where value >= 0 and value <= 130`) | ✓ |
| Constraint **enforcement** at construction (gated; aborts on violation) | ✓ |
| Compound types (`type Person = { name: Name, age: Age }`) | ✓ |
| Optional types (`T?`) and `if let` unwrapping | ✓ |
| Array types (`T[]`) | ✓ |
| `Bytes` — raw binary buffer primitive (distinct from `String`) | ✓ |
| Result type `T!` with `ok`/`err` and `?` propagation | ✓ |
| Interfaces with vtable dispatch | ✓ |
| Generics | ✗ (planned) |
| Sum types / enums with exhaustive `match` | ✗ (planned) |

## Functions & control flow

| Feature | Status |
|---------|--------|
| Seven function kinds (`mapper`, `projector`, `predicate`, `consumer`, `producer`, `reducer`, `creator`) | ✓ |
| Purity enforcement (pure kinds cannot mutate or be `async`) | ✓ (reference checks) |
| `where`-guarded overloading (runtime overload selection by guard) | ✓ |
| `match` (literal / string / bool / bound-ident / `_` patterns) | ✓ |
| `for` loops over arrays | ✓ |
| `if` / `if let` | ✓ |
| `scope` blocks | ✓ (compiled as C blocks) |
| `async` functions | ✓ (compiled synchronously in the C backend) |
| `unsafe` blocks | ✓ |

## Dependency injection & IoC

| Feature | Status |
|---------|--------|
| **Automatic** dependency injection (implementations discovered; `bind` optional) | ✓ |
| Classes with a `deps { ... }` block | ✓ |
| Dep disambiguation: `where` guard, list `I[]`, `or` fallback, optional `I?` | ✓ |
| Function-level deps: `kind { d: I } name(...)` | ✓ |
| `singleton` / `transient` scopes (via optional `bind ... as`) | ✓ |
| `App.resolve(Interface)` at use sites | ✓ |
| `module App { bind I -> Impl ... }` overrides | ✓ |

## Modules & interop

| Feature | Status |
|---------|--------|
| Multi-file `import "file.x"` (recursive, de-duplicated) | ✓ |
| `namespace a.b` (top-level symbol isolation; cross-file `a.b.Name`) | ✓ |
| String concatenation with `+` (auto-coercion of scalars) | ✓ |
| `extern "C"` blocks | ✓ (declaration) |
| `export "C"` functions | ✓ |

## Standard library (`std/*.x`)

| Module | Provides |
|--------|----------|
| `math` | sqrt/pow/exp/ln/trig/floor/ceil/round, `pi`, `e` |
| `text` | length/substring/trim/case/contains/indexOf/replace/repeat, **split/join** |
| `bytes` | length/at/slice/concat/fromString/toString for `Bytes` |
| `convert` | string ↔ number/integer parsing |
| `io` | console `println`/`print`/`eprintln`, `readLine`/`eof` |
| `fs` | read/write text & **bytes**, exists/isDir/isFile, size/mtime, remove/rename/copy, mkdir/mkdirAll, cwd, listDir |
| `path` | join/dirname/basename/ext/stripExt (pure) |
| `net` | **TCP sockets, client + server** (dial/listen/accept/send/recv/close) |
| `process` | env vars, run shell command, exit |
| `time` | monotonic nanos, sleep |

## Toolchain

| Feature | Status |
|---------|--------|
| Self-hosting compiler (written in X, compiles its own source) | ✓ |
| Native binaries via C99 backend (compiler invokes `cc`) | ✓ |
| `file:line` diagnostics on lexer/parser errors | ✓ (initial) |
| REPL / run tool (`x`) | ✓ |
| Editor support: Tree-sitter grammar, Zed, Vim | ✓ |
| Full ownership / borrow checking | ✗ (relies on C; planned) |
| LLVM backend | ✗ (uses C as the intermediate) |
| Result-of-array `T[]!` | ✗ (use `T[]`; codegen limitation) |
