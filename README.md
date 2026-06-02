# xc — The X Language Compiler (self-hosting)

A compiler for the X programming language. **The compiler is written in X**
(`compiler/xc.x`) and is **self-hosting** — it compiles its own source. The only
non-X code is the C runtime, which every compiler that targets C/native must ship.

## Compiler pipeline

```
source.x (+ imported files)
  ↓ load     – resolve `import`s, apply `namespace` prefixing (compiler/xc.x)
  ↓ lex      – tokeniser
  ↓ parse    – recursive-descent parser
  ↓ codegen  – C99 generation (DI, vtables, refined types, overloads, …)
  ↓ cc       – C → native binary (invoked automatically)
```

## Documentation

Full docs live in `docs/` as plain Markdown — start at `docs/index.md`. An
optional `mkdocs.yml` is included for rendering them as a site.

## Build & run

```sh
# 1. Bootstrap from source with only a C compiler. Builds ./compiler/xc and ./bin/x
#    (the REPL/run tool). stage0.c is the X compiler's own C output; cc turns it
#    into a working xc, which then rebuilds itself from compiler/xc.x.
./compiler/bootstrap.sh

# 2. Compile an X program to a native executable (xc invokes cc for you).
#    Build artifacts go to ./build (override with XC_OUT).
export XC_RUNTIME="$PWD/runtime"
./compiler/xc examples/greeting.x      # -> build/greeting
./build/greeting

# Or compile-and-run, or start the REPL, with the `x` tool:
export XC="$PWD/compiler/xc"
./bin/x examples/greeting.x                # compile + run
./bin/x                                    # interactive REPL

# 3. Verify self-hosting (3-stage byte-identical fixpoint):
./compiler/selfhost.sh
```

The compiler's own source is **multi-file** (`compiler/{lexer,parser,codegen,driver}.x`,
imported by the `xc.x` manifest) — the same `import`/`namespace` mechanism your
projects use.

`XC_RUNTIME` points at the runtime dir (default `runtime`). When compiling the
compiler itself, set `XC_HELPERS=compiler/xc_helpers.c` so its array/IO/`cc`
primitives are linked in (the bootstrap/selfhost scripts do this for you).

## Multi-file projects: `import` and `namespace`

Split a project across files. `import "rel/path.x"` splices another file's
declarations into the unit (recursive, de-duplicated by path). `namespace a.b`
prefixes a file's top-level names so independently authored files can reuse
short names without colliding; reference them across files as `a.b.Name`.

```x
// examples/proj/math.x
namespace math
mapper add(a: Number, b: Number) -> Number { return a + b }
mapper square(x: Number) -> Number { return x * x }
```
```x
// examples/proj/main.x
import "math.x"
import "text.x"
async entry main(args: String[]) -> Integer {
    system.stdout.writeln("2 + 3 = " + math.add(2, 3))   // math.add -> math__add
    return 0
}
```

```sh
./compiler/xc examples/proj/main.x && ./build/main
```

## Language features supported

| Feature | Status |
|---------|--------|
| Refined types (`type Age = Number where value >= 0 and value <= 130`) | ✓ |
| Constraint **enforcement** at construction (gated; aborts on violation) | ✓ |
| Compound types (`type Person = { name: Name, age: Age }`) | ✓ |
| Interfaces with vtable dispatch | ✓ |
| Seven function kinds (`mapper`, `projector`, `predicate`, `consumer`, `producer`, `reducer`, `creator`) | ✓ |
| `where`-guarded overloading (same name, runtime overload selection by guard) | ✓ |
| Multi-file `import "file.x"` (recursive, de-duplicated) | ✓ |
| `namespace a.b` (top-level symbol isolation; cross-file `a.b.Name`) | ✓ |
| Error handling: `T!` Result, `ok`/`err`, `?` propagation | ✓ |
| `match` (literal / string / bool / bound-ident / `_` patterns) | ✓ |
| Standard library (`std/*.x`: math, text, convert, io, fs, process, time) | ✓ |
| Purity enforcement (mappers/projectors/predicates/reducers cannot mutate or be async) | ✓ (reference checks) |
| Classes with `deps {}` block | ✓ |
| **Automatic** dependency injection (implementations discovered; `bind` optional) | ✓ |
| Dep disambiguation: `where`, list `I[]`, `or` fallback, `I?` optional | ✓ |
| Function-level deps: `kind { d: I } name(...)` | ✓ |
| `singleton` / `transient` scopes (via optional `bind ... as`) | ✓ |
| `App.resolve(Interface)` at use sites | ✓ |
| `async` functions (compiled as synchronous in C backend) | ✓ |
| `for` loops over arrays | ✓ |
| `if` / `if let` for optional unwrapping | ✓ |
| `scope` blocks | ✓ (compiled as C blocks) |
| `unsafe` blocks | ✓ |
| Optional types (`T?`) | ✓ |
| Array types (`T[]`) | ✓ |
| String concatenation with `+` (auto-coercion) | ✓ |
| `extern "C"` blocks | ✓ (declaration) |
| `export "C"` functions | ✓ |
| Constraint checks at construction boundaries | ✓ (runtime abort) |
| Generics | ✗ (v2) |
| Full ownership/borrow checking | ✗ (v2, relies on C) |
| LLVM backend | ✗ (uses C as intermediate) |

## Examples

```x
// Refined type with constraint
type Age = Number where value >= 0 and value <= 130

// Compound type
type Person = { name: String, age: Age }

// Pure function
predicate isAdult(p: Person) {
    return p.age >= 18
}

// Interface
interface Greeter {
    mapper greet(p: Person) -> String
}

// Class implementing interface with injected deps
class FriendlyGreeter implements Greeter {
    deps {
        logger: Logger
    }
    mapper greet(p: Person) -> String {
        return "Hello, " + p.name
    }
}

// DI module
module App {
    bind Logger  -> ConsoleLogger  as singleton
    bind Greeter -> FriendlyGreeter as transient
}

// Entry point
async entry main(args: String[]) -> Integer {
    let greeter = App.resolve(Greeter)
    let p = Person { name: "Ada", age: 36 }
    system.stdout.writeln(greeter.greet(p))
    return 0
}
```

## `where`-guarded overloading

A function may be declared multiple times under the same name, each with a
`where` guard over its parameters. At a call site the compiler generates a
dispatcher that evaluates the guards **in declaration order** and invokes the
first overload whose guard holds. An unguarded overload (if present) is the
default; if none matches and there is no default, the program panics.

```x
type ApiResponse = { status: Number, body: String }

mapper mapResponse(res: ApiResponse) -> String where res.status == 200 {
    return "OK: " + res.body
}
mapper mapResponse(res: ApiResponse) -> String where res.status == 404 {
    return "Not Found"
}
mapper mapResponse(res: ApiResponse) -> String where res.status >= 500 {
    return "Server Error (" + res.status + ")"
}
mapper mapResponse(res: ApiResponse) -> String {        // default
    return "Unhandled status: " + res.status
}
```

Grammar: `function_decl ::= ("async")? function_kind Ident "(" params ")" ("->" type)? ("where" expr)? block`

Each overload compiles to `xc_<name>__ovlN`, and a dispatcher `xc_<name>`
selects among them:

```c
static xc_string_t xc_mapResponse(xc_ApiResponse_t res) {
    if ((res.status == 200LL)) return xc_mapResponse__ovl0(res);
    if ((res.status == 404LL)) return xc_mapResponse__ovl1(res);
    if ((res.status >= 500LL)) return xc_mapResponse__ovl2(res);
    return xc_mapResponse__ovl3(res);   /* unguarded default */
}
```

See `examples/overload.x`.

## Error handling: `Result`, `ok`/`err`, `?`

`T!` is the result type "a `T` or an error" (the error is a string in v1).
Construct results with `ok(value)` / `err("message")`, and propagate failures
with the postfix `?` operator: `let x = expr?` returns early with the `Err` if
`expr` failed, otherwise binds `x` to the unwrapped `Ok` value. Inspect a result
with `isOk(r)` / `isErr(r)` and read `r.value` / `r.err`.

```x
type Age = Number where value >= 0 and value <= 130

mapper checkAge(n: Number) -> Age! {
    if n < 0   { return err("age is negative") }
    if n > 130 { return err("age too large") }
    return ok(n)
}

mapper classify(n: Number) -> String! {
    let a = checkAge(n)?            // propagates the Err if checkAge failed
    if a < 18 { return ok("minor") }
    return ok("adult")
}

consumer report(label: String, r: String!) {
    if isOk(r) { system.stdout.writeln(label + " -> " + r.value) }
    else       { system.stdout.writeln(label + " -> error: " + r.err) }
}
```

A `Result<T>` lowers to `struct { bool ok; T value; xc_string_t err; }`; `?`
lowers to an early-return of the propagated error. See `examples/errors.x`.

## `match`

`match` lowers to an if/else chain over the subject. Patterns: integer / float /
string / bool literals, an identifier (binds the subject as a catch-all), and
`_` (wildcard). Arm bodies are a block or a single expression.

```x
mapper dayName(d: Number) -> String {
    match d {
        0 -> { return "Sun" }
        6 -> { return "Sat" }
        n -> { return "weekday " + n }   // binds n
    }
}
```

## Project layout

```
compiler/
├── xc.x            Manifest: imports the parts below
├── lexer.x parser.x codegen.x driver.x   The compiler, written in X
├── repl.x          The REPL / run tool (compiled to ./bin/x)
├── xc_helpers.c    C primitives xc.x declares via extern "C"
│                   (growable typed arrays, file I/O, cc invocation)
├── xc.stage0.c     Generated C of the compiler — bootstrap seed (cc-only build)
├── xc              Native compiler binary (produced by bootstrap.sh)
├── bootstrap.sh    Build the compiler (+ ./bin/x) from source with only cc
├── build.sh        Compile an X program with the X compiler
└── selfhost.sh     3-stage self-hosting fixpoint verification
runtime/
├── runtime.h       C runtime header (primitive types, string/array helpers)
└── runtime.c       C runtime (regex, string ops, file I/O, stdlib primitives)
std/                The standard library (X modules wrapping the runtime)
├── math.x text.x convert.x io.x fs.x process.x time.x
└── all.x           imports them all
examples/
├── hello.x refined_types.x greeting.x features.x overload.x errors.x
├── stdlib_demo.x di_auto.x
├── proj/           multi-file example (import + namespace)
└── showcase/       full project (folder layout) exercising most features
editors/
├── tree-sitter-x/  Tree-sitter grammar for X
├── zed/            Zed editor extension (highlighting, outline, comments)
└── vim/            Vim / Neovim syntax + filetype plugin
bin/                the REPL/run tool `x` (built by bootstrap.sh; git-ignored)
build/              all compiled binaries + generated C land here (XC_OUT)
```

## Editor support

A Tree-sitter grammar and a **Zed** extension live in `editors/` — see
`editors/README.md`. The grammar parses every `.x` file in this repo (examples,
stdlib, and the compiler itself) with no errors.

### Bootstrapping note

The repository is bootstrappable from source with only a C compiler:
`compiler/xc.stage0.c` is the X compiler's own emitted C, so
`cc xc.stage0.c runtime/runtime.c -o xc` yields a working compiler, which then
rebuilds itself from `compiler/xc.x`. `selfhost.sh` proves the fixpoint
(gen0/gen1/gen2 emit byte-identical C). The C runtime is intrinsic — the X
equivalent of libc/libcore — not compiler logic.
