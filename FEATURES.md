# Xi — language feature matrix

Status of language and toolchain features. See [`docs/`](docs/) for the full
guide and [`README.md`](README.md) for a tour with examples.

## Type system

| Feature | Status |
|---------|--------|
| Refined types (`type Age = Number where value >= 0 and value <= 130`) | ✓ |
| Constraint **enforcement** at construction (gated; aborts on violation) | ✓ |
| Compound types (`type Person = { name: Name, age: Age }`) | ✓ |
| Sum / algebraic types (`type Shape = \| Circle { r: Number } \| Empty`), matched with `match` | ✓ |
| Optional types (`T?`) and `if let` unwrapping | ✓ |
| Array types (`T[]`) | ✓ |
| `List<T>` — growable mutable generic list (`empty List<T>`, push/get/set/len/removeAt; `for x in`) | ✓ |
| `Set<T>` — hash set of unique elements (`empty Set<T>`, add/contains/remove/len/isEmpty/clear/items; `for x in`) | ✓ |
| `Map<K, V>` — hash map, K primitive/String (`empty Map<K, V>`, put/get/getOr/has/remove/len/clear/keys/values) | ✓ |
| Collection builders (`listOf(...)`, `setOf(...)`, `mapOf(k to v, ...)`) | ✓ |
| List functional API via lambdas — map/filter/fold/reduce/sumOf/count/any/all/none/forEach/joinToString/mapIndexed/take/drop/takeWhile/dropWhile/reversed/distinct/flatMap/first/last/toSet (inlined) | ✓ |
| Type aliases incl. plural/array (`type People = Person[]`, `type Name = String`) | ✓ |
| `empty T` — the zero value of any type (struct all-zero, array empty) | ✓ |
| `atom` — active-state store: immutable `state` + `transition` reducers + `undo()`/`canUndo()` time-travel | ✓ |
| `machine` — finite state machine (named states, machine-wide `data`, transition params, `where` guards, `update`, `.can()`, `IllegalTransition`) | ✓ |
| Machine **static checks** (unknown-state errors; unreachable / dead-end warnings) | ✓ |
| `Bytes` — raw binary buffer primitive (distinct from `String`) | ✓ |
| Result type `T!` with `ok`/`err` and `?` propagation | ✓ |
| Interfaces with vtable dispatch | ✓ |
| `entry` / function / method dependency injection (`(dep: I)` simple or `{ dep: I where … }` form) | ✓ |
| Leveled `Logger` interface (`print`/`debug`/`info`/`warn`/`error`/`fatal`/`audit`) + `ConsoleLogger` default (`std/log`) | ✓ |
| Interface **default methods** (method bodies inherited unless overridden) | ✓ |
| Generics | ✗ (planned) |

## Functions & control flow

| Feature | Status |
|---------|--------|
| Eight function kinds (`mapper`, `projector`, `predicate`, `consumer`, `producer`, `reducer`, `creator`, `action`) | ✓ |
| Decision tables — `decision` kind (`when <cond> => <result>`, `hit first`) | ✓ (MVP) |
| Purity enforcement (pure kinds cannot mutate or be `async`) | ✓ (reference checks) |
| Inline function bodies (`mapper f(x) => expr`, sugar for `{ return expr }`; any kind, methods, overloads) | ✓ |
| `where`-guarded overloading — free functions **and methods** (runtime overload selection by guard) | ✓ |
| `match` (literal / string / bool / bound-ident / variant / `_` / `else` patterns; multi-key `(a, b)` arms; inline `-> expr` or `{ block }` bodies) | ✓ |
| Interrupts — resumable conditions (`interrupt`/`signal`/`try`/`catch`, `skip`+`recover`) | ✓ (MVP) |
| `for` loops over arrays | ✓ |
| `for` loops over `List<T>` / `Set<T>` | ✓ |
| Integer ranges (`a..b`, `until`, `downTo`, `step`) in `for` and as values | ✓ |
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
| Function/method/entry deps: `kind (d: I) name(...)` (simple) or `{ … }` (where/or/list) | ✓ |
| `singleton` / `transient` scopes (via optional `bind ... as`) | ✓ |
| `App.resolve(Interface)` at use sites | ✓ |
| `module App { bind I -> Impl ... }` overrides | ✓ |
| `module` metadata (`id`/`name`/`description`/`version`/`license`); `id` sets the binary name | ✓ |

## Modules & interop

| Feature | Status |
|---------|--------|
| Multi-file `import "file.xi"` (recursive, de-duplicated) | ✓ |
| `namespace a.b` (top-level symbol isolation; cross-file `a.b.Name`) | ✓ |
| String concatenation with `+` (auto-coercion of scalars) | ✓ |
| `extern "C"` blocks | ✓ (declaration) |
| `export "C"` functions | ✓ |

## Standard library (`std/*.xi`)

| Module | Provides |
|--------|----------|
| `math` | sqrt/pow/exp/ln/trig/floor/ceil/round, `pi`, `e` |
| `text` | length/substring/trim/case/contains/indexOf/replace/repeat, **split/join** |
| `bytes` | length/at/slice/concat/fromString/toString for `Bytes` |
| `convert` | string ↔ number/integer parsing |
| `json` / `yaml` / `xml` | **serialization** — build/parse/stringify; derived codecs for events & compounds |
| `crypto` | **SHA-256/SHA-1/MD5, HMAC-SHA256, hex/base64, CSPRNG** (`randomBytes`/`randomHex`) |
| `events` | **typed publish/subscribe** — `publish(topic, dto)` + `listener … on "topic"`, in-memory default bus, sync or async (`runAsync`) delivery |
| `web` | **REST framework** — `WebRequestHandler` + `where`-overloaded `handle`, `res.send`/`req.parse` via `WebTransport`, blocking HTTP/1.1 server, optional HTTPS (`serveTLS`) + HTTP/2 (`serveHttp2`) via `XC_TLS=1`/`XC_HTTP2=1` |
| `thread` | **share-nothing threads** — `parallel { }` blocks + thread-safe channels carrying strings **or structured data** (`send(dto)`/`recv(T)`/`close`), `Thread` handle (`stop`/`wait`/`running`); per-thread arena freed on exit |
| `io` | console `println`/`print`/`eprintln`, `readLine`/`eof` |
| `fs` | read/write text & **bytes**, exists/isDir/isFile, size/mtime, remove/rename/copy, mkdir/mkdirAll, cwd, listDir |
| `path` | join/dirname/basename/ext/stripExt (pure) |
| `net` | **TCP sockets, client + server** (dial/listen/accept/send/recv/close) |
| `http` | **HTTP/1.1 client** over `net` (get/post/request, header lookup, URL parse); `https://` with `XC_TLS=1` |
| `process` | env vars, run shell command, exit |
| `time` | monotonic nanos, sleep |

## Toolchain

| Feature | Status |
|---------|--------|
| Self-hosting compiler (written in Xi, compiles its own source) | ✓ |
| Native binaries via C99 backend (compiler invokes `cc`) | ✓ |
| `file:line` diagnostics on lexer/parser errors | ✓ (initial) |
| REPL / run tool (`xi`) | ✓ |
| `xi version` and `xi update` (self-update from GitHub releases) | ✓ |
| `xi skill` — print the AI-agent language guide (`docs/skill.md`) | ✓ |
| Built-in testing — `test "…" { assert … }`, `xi test`, `module Test` doubles | ✓ |
| Editor support: Tree-sitter grammar, Zed, Vim | ✓ |
| Full ownership / borrow checking | ✗ (relies on C; planned) |
| LLVM backend | ✗ (uses C as the intermediate) |
| Result-of-array `T[]!` | ✗ (use `T[]`; codegen limitation) |
