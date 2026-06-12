# Xi language — AI agent skill

A complete, copy-pasteable guide to writing **Xi** (Ξ) code. Xi compiles to C99
and then to a native binary. Fetch the latest copy with `xi skill`.

## Golden rules

- Every program has one `async entry … main(args: String[]) { … }` and a
  `module App {}` (the DI container; add `bind`s inside it only to override
  defaults; the entry may also live *inside* the module block). `entry` always
  returns `Integer`, so `-> Integer` is optional and a body with no `return`
  exits `0`; add `-> Integer` + `return <code>` for a non-zero exit.
- **There is no `null`.** Absence is modeled with optionals (`T?` + `if let`) or
  results (`T!`). Never write `null`.
- Statements are newline-separated; no semicolons. Blocks use `{ }`.
- Output: inject a `Logger` (`import "std/log.xi"`) and call `logger.info(...)`,
  or use `system.stdout.writeln(...)` directly.
- String concatenation is `+`; scalars (Integer/Number/Bool) auto-coerce to text
  inside a `+` chain. `int_to_string(n)` also works.

## Hello, world

```x
import "std/log.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.info("Hello, world!")
    return 0
}

module App {}
```

Compile & run: `xc hello.xi` (→ `build/hello`) or `xi hello.xi` (compile + run).

## Comments

```x
// line comment
/* block comment */
```

## Values & variables

```x
let n = 21            // immutable-style binding; reassignable with =
n = n + 1
let pi: Number = 3.14 // optional type annotation
```

## Primitive types

| Type | Notes |
|------|-------|
| `Integer` | 64-bit signed (`42`, `-7`) |
| `Number` | double (`3.14`, `2.0`) |
| `Bool` | `true` / `false` |
| `String` | UTF-8 text (`"hi"`); escapes `\n` `\t` `\"` `\\` |
| `Char` | a Unicode scalar |
| `Bytes` | raw binary buffer (see `std/bytes`) |

Operators: `+ - * /`, comparisons `== != < > <= >=`, logical `and or not`.

## Compound types (structs)

```x
type Person = { name: String, age: Integer }

let p = Person { name: "Ada", age: 36 }   // construct
let who = p.name                          // field access
```

## Refined types (constraints)

```x
type Age = Number where value >= 0 and value <= 130
// constructing an out-of-range Age aborts at runtime (when checks are enabled)
```

## Type aliases

```x
type Name   = String
type People = Person[]      // plural/array alias
```

## `empty` — the zero value

```x
let p = empty Person          // all fields zeroed
let xs = empty List<Integer>  // empty collection
```

## Optionals (no null)

```x
type Row = { id: Integer }
mapper find(id: Integer) -> Row? { ... }     // may return none

if let row = find(7) {        // unwraps only if present
    use(row)
}
```

## Results & error handling

```x
mapper checkAge(n: Number) -> Age! {          // T! is a Result
    if n < 0   { return err("age is negative") }
    if n > 130 { return err("age too large") }
    return ok(n)
}

mapper classify(n: Number) -> String! {
    let a = checkAge(n)?                       // `?` propagates an err
    if a < 18 { return ok("minor") }
    return ok("adult")
}

let r = classify(25)
if isOk(r) { use(r.value) } else { handle(r.err) }   // isOk/isErr, .value/.err
```

## Functions — the eight kinds

Pick the kind by intent (purity is enforced for the pure kinds):

| Kind | Meaning |
|------|---------|
| `mapper` | `(T) -> U` pure transform |
| `projector` | extracts/derives a field-like value |
| `predicate` | returns `Bool` |
| `consumer` | side effects, returns nothing |
| `producer` | produces a value (often I/O) |
| `reducer` | `(Acc, T) -> Acc` |
| `creator` | constructs instances |
| `action` | impure; may mutate; e.g. a web handler |

```x
mapper add(a: Integer, b: Integer) -> Integer { return a + b }
mapper square(x: Integer) -> Integer => x * x      // inline body with =>
predicate isEven(n: Integer) { return n % 2 == 0 }
consumer greet(name: String) { system.stdout.writeln("hi " + name) }
```

`where`-guarded overloads (selected at runtime by the guard):

```x
mapper fee(amount: Number) -> Number where amount > 100 => amount * 0.9
mapper fee(amount: Number) -> Number => amount
```

## Control flow

```x
if cond { ... } else { ... }
if let x = maybe { ... }            // optional unwrap

while cond { ... }
loop { ...; if done { break } }      // infinite loop; break / continue

for item in items { ... }            // arrays, List<T>, Set<T>
for i in 1..5 { ... }                // ranges (see below)

scope { ... }                        // a plain block scope
```

### match

```x
match code {
    200            -> { return "ok" }
    404            -> "missing"            // inline arm (returned)
    ("BA", "BD")   -> "multi-key"          // any of these keys
    n              -> "other " + n         // binds n
    else           -> "default"            // else / _ for default
}
```

### Ranges

```x
for i in 1..5            { }   // 1 2 3 4 5  (inclusive)
for i in 0 until 5       { }   // 0 1 2 3 4  (exclusive end)
for i in 10 downTo 1     { }   // counts down
for i in 0..100 step 10  { }   // custom stride
let r = 2..4                   // ranges are values too
```

## Collections (built-in generics)

Create with `empty` or a builder; no import needed.

```x
// List<T> — growable ordered list
let xs = empty List<Integer>
xs.push(10)  xs.get(0)  xs.set(0, 9)  xs.len()  xs.isEmpty()  xs.removeAt(0)  xs.clear()
for x in xs { ... }

// Set<T> — unique elements (String compared by content)
let s = empty Set<String>
s.add("a")  s.contains("a")  s.remove("a")  s.len()  s.items()   // items() -> List<T>
for e in s { ... }

// Map<K, V> — K is a primitive or String; V is any type
let m = empty Map<String, Integer>
m.put("ada", 36)  m.get("ada")  m.getOr("zz", 0)  m.has("ada")  m.remove("ada")
m.len()  m.keys()  m.values()                 // keys()/values() -> List
for k in m.keys() { let v = m.get(k) ... }    // iterate via keys()

// Builders (types inferred from the first element)
let a = listOf(2, 3, 5)
let b = setOf("x", "y", "x")
let c = mapOf("fr" to "Paris", "jp" to "Tokyo")
```

Note: plain arrays `T[]` use `.len` and `.data[i]` (e.g. `args.len`,
`args.data[0]`); `List<T>` uses `.len()` and `.get(i)`.

## Dependency injection

Depend on an **interface**; the compiler injects the implementor automatically
(no registration needed when there's one implementor).

```x
import "std/log.xi"

interface Greeter { mapper greet(name: String) -> String }

class FriendlyGreeter implements Greeter {
    deps {}                                            // this class's dependencies
    mapper greet(name: String) -> String => "Hey " + name + "!"
}

class OrderService {
    deps { greeter: Greeter, logger: Logger }          // injected fields
    consumer place(name: String) { logger.info(greeter.greet(name)) }
}

async entry (logger: Logger) main(args: String[]) -> Integer {   // entry deps in ()
    App.resolve(OrderService).place("Ada")
    return 0
}

module App {}     // add `bind Greeter -> FormalGreeter` here to override
```

Function/method deps use the same `(dep: I)` form:
`consumer (logger: Logger) report(msg: String) { logger.info(msg) }`.

## Module metadata

The `module` block can also carry package metadata. `id` sets the **compiled
binary's name** (otherwise it's the source filename). The block may be anonymous
(`module { ... }`) or named (`module App { ... }`), and metadata can sit
alongside `bind`s.

```x
module App {
    id          = "file-server"     // -> binary named `file-server`
    name        = "File Server"     // name/description/version/license = metadata
    version     = "0.12"
    license     = "MIT"
    includes    = ["./**"]          // files that belong to this module (default)
    excludes    = ["scratch/**"]    // ...minus these
    dependencies = ["https://example.com/xi-sqlite-0.1.0.tar.gz"]  // source archives

    async entry (logger: Logger) main(args: String[]) {  // entry can live inside
        logger.info("up")
    }
}
```
(The `entry` may also be top-level with a separate `module App {}` — both work.)

Multiple modules can share a folder (each owns its `entry main` + `includes`/
`excludes`); build one with `xc file.xi` or all with `xc --all`.

**Dependencies:** list `.tar.gz`/`.zip` source-archive URLs in `dependencies`,
then `xi install [file]` downloads + extracts them into `./modules`, which `xc`
auto-gathers at build time (reference their functions by `namespace` — no
`import` needed). A library dependency is plain Xi source with a `namespace` and
no `entry`/`module`.

## Logging (std/log)

Inject `Logger`; levels: `debug` `info` `warn` `error` `fatal` (warn/error/fatal
→ stderr, the rest → stdout), plus `audit` and unprefixed `print`.

```x
logger.info("started")
logger.warn("low disk")
logger.error("request failed")
```

## Sum / algebraic types

```x
type Shape = | Circle { r: Number } | Square { side: Number } | Empty

mapper area(s: Shape) -> Number {
    match s {
        Circle c -> 3.14159 * c.r * c.r
        Square q -> q.side * q.side
        else     -> 0.0
    }
}
```

## Decision tables (`decision` kind)

```x
decision quote(score: Number, base: Number) -> Number {
    hit first
    when score >= 700 => base * 0.9
    when score >= 500 => base
    else              => base * 2
}
```

## Interrupts (resumable conditions)

```x
interrupt Over { x: Integer }

producer calc(n: Integer) interrupts Over {
    if n > 100 { signal Over { x: n } recover { system.stdout.writeln("clamped") } }
    system.stdout.writeln("done " + n)
}

// handler decides: recover (run the restart, continue) or skip (abandon)
try { calc(150) } catch e: Over { if e.x > 200 { skip } else { recover } }
```

Note: a `catch`/`recover` handler runs as an isolated frame — it can see globals
(`system.stdout`) but **not** injected locals like `logger`.

## Atoms & machines (brief)

An **atom** is an active-state store: a separate `state` type, an `initial`
value, and `transition` reducers that take the current state `s` first and return
a new state. Call a transition with just the extra args; read with `.current`.

```x
state Cart = { items: Integer, total: Number }

atom cart {
    initial Cart { items: 0, total: 0.0 }
    transition addItem(s: Cart, price: Number) -> Cart {
        return Cart { items: s.items + 1, total: s.total + price }
    }
}
// cart.addItem(9.99)   cart.current.items   cart.undo()   cart.canUndo()
```

A **machine** is a finite state machine value: `states`, the `initial` one,
optional `terminal -`, and transitions `name : From... -> To`.

```x
machine Door {
    states  Closed, Open, Locked
    initial Closed
    open : Closed       -> Open
    lock : Closed, Open -> Locked
}
// let d = Door.start();  d = d.open();  d.state;  d.can(lock)
// an illegal transition signals IllegalTransition (handle with try/catch).
```

## Standard library

`import "std/<name>.xi"`: `math`, `text`, `convert`, `bytes`, `json` / `yaml` /
`xml` (serialization), `crypto`, `events`, `web`, `thread`, `io`, `fs`, `path`,
`net`, `http`, `process`, `time`, `log`. Namespaced calls, e.g.
`math.sqrt(2.0)`, `text.toUpper("hi")`, `json.stringify(v)`.

## Testing

Built-in. Write `test "name" { assert <expr> }`; run with `xi test file.xi`.

```x
mapper add(a: Integer, b: Integer) -> Integer { return a + b }

test "addition" {
    assert add(2, 3) == 5
}

test "uses a fake" (clock: Clock) {     // deps injected; Test doubles below
    assert clock.now() == 42
}

module Test { bind Clock -> FakeClock } // layered over App; ignored in normal builds
```

- `assert <expr>` works anywhere: in a `test` a failure aborts just that test and
  the run continues; in normal code it prints `file:line` and aborts the process.
- `xi test` exits nonzero if any test fails. `test` cases are excluded from normal
  `xc` builds. Put tests in `*_test.xi` files.

## Typed configuration (std/config)

Describe config as an interface and bind it to a file; the compiler loads +
deserializes it (primitives directly, compounds via codec; YAML or JSON):

```x
import "std/config.xi"
type TaxConfig = { percent: Number, rate: Integer }
interface AppConfig {
    mapper projectName() -> String      // method name = top-level key
    mapper tax() -> TaxConfig
}
module App  { bind AppConfig -> readConfig("application.yaml") }
module Test { bind AppConfig -> readConfig("application-test.yaml") }   // wins under `xi test`
```

Inject `AppConfig` like any dependency. A missing key yields the zero value.
Or read one file into a value generically (JSON/YAML/XML by extension):

```x
let tax = readConfig<Tax>("tax.yaml")
```

Hot-reload: inject `ApplicationConfig`, call `cfg.watch("app.yaml", "config.changed")`,
run `Events.runAsync()`, and handle `ConfigChanged` in a `listener`.

## C interop / porting a C library (`extern "C"`)

Declare the C functions in an `extern "C"` block and add a build directive so
`xc` links the library. The signatures *are* the binding.

```x
import "std/ffi.xi"
extern "C" {
    link "sqlite3"                                       // -> -lsqlite3
    // also: pkg "name", cflags "-I…", ldflags "-L…", include "<h.h>"
    producer sqlite3_open(path: cstring, ppDb: &mut Ptr) -> Integer
    producer sqlite3_close(db: Ptr) -> Integer
}

let db = empty Ptr                                       // empty Ptr = NULL
sqlite3_open(toCString(":memory:"), &mut db)             // &mut x = C out-param
```

- `Ptr` = `void*` (opaque handle); `cstring` = `const char*`; `&mut x` = address-of
  (out-params); `empty Ptr` = null.
- A Xi `String` is not a `cstring` — bridge with `toCString(s)` / `fromCString(p)`
  from `std/ffi`.
- Declare externs **or** `include` a header for the same function, not both
  (conflicting C declarations). For a simple port, externs + `link` only.

## A complete program

```x
import "std/log.xi"
import "std/convert.xi"

type Item = { name: String, qty: Integer }

mapper totalQty(items: List<Item>) -> Integer {
    let sum = 0
    for it in items { sum = sum + it.qty }
    return sum
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let cart = empty List<Item>
    cart.push(Item { name: "pen", qty: 2 })
    cart.push(Item { name: "book", qty: 5 })

    let prices = mapOf("pen" to 3, "book" to 9)
    for it in cart {
        logger.info(it.name + " x" + int_to_string(it.qty)
                  + " @ " + int_to_string(prices.getOr(it.name, 0)))
    }
    logger.info("total qty = " + int_to_string(totalQty(cart)))
    return 0
}

module App {}
```

## Common mistakes to avoid

- Forgetting `module App {}` at the end, or the `async entry … main` signature.
- Using `null` — use `T?` + `if let`, or `T!` + `ok`/`err`.
- Confusing array vs List access: arrays use `.len` / `.data[i]`; `List` uses
  `.len()` / `.get(i)`.
- `Map.get(k)` aborts on a missing key — guard with `has` or use `getOr`.
- Using an injected `logger` inside an interrupt `catch`/`recover` block (use
  `system.stdout` there).
- Adding semicolons (Xi uses newlines).
