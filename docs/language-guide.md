# Language guide

## Primitive types

`Number` (f64), `Integer` (i64), `Bool`, `String`, `Char`, `Timestamp`, `Size`,
`Void`.

## Refined types

A refined type narrows a base type with a `where` constraint; `value` refers to
the underlying value.

```x
type Age      = Number where value >= 0 and value <= 130
type Email    = String where value matches /^[^@\s]+@[^@\s]+\.[^@\s]+$/
type NonEmpty = String where value.length > 0
```

**Construction is gated.** Whenever a value is placed into a refined-type field
of a compound literal, its constraint is checked; a violation aborts the program
with a clear message. Partially-valid instances cannot exist.

```x
type Person = { name: NonEmpty, age: Age }
let ok  = Person { name: "Ada", age: 30 }
let bad = Person { age: 999 }    // xc: constraint violation: Age  -> abort
```

Constraints may use comparisons/`and`/`or`, `value.length` (string length), and
`value matches /regex/`.

## Compound types

```x
type Person = { name: NonEmpty, age: Age, email: Email }
type Team   = { lead: Person, members: Person[] }
```

`T?` is an optional, `T[]` an array, `T!` a [result](error-handling.md).

## Sum (algebraic) types

A sum type's value is exactly **one of several variants**, each optionally
carrying its own fields. Declare the variants with `|`:

```x
type Shape =
    | Circle { radius: Number }
    | Rect   { w: Number, h: Number }
    | Empty                              // a nullary variant

type Color = | Red | Green | Blue        // no payloads == a plain enum
```

Construct a variant by name (`Circle { radius: 2.0 }`, or just `Empty`).
Deconstruct with `match` — a variant pattern may bind the payload:

```x
mapper area(s: Shape) -> Number {
    match s {
        Circle c -> { return 3.14159 * c.radius * c.radius }   // c is the payload
        Rect r   -> { return r.w * r.h }
        Empty    -> { return 0.0 }
    }
    return 0.0
}
```

A sum type is an ordinary type: use it in fields (`type Light = { color: Color }`),
arrays (`Shape[]`), parameters, and returns. Variant names must be unique
across all sum types in the program.

## Type aliases

A `type` can alias another type — handy for readable *plural* names for arrays:

```x
type Person = { name: String, age: Number }
type People = Person[]          // plural alias for an array
type Name   = String            // plain alias

mapper headcount(p: People) -> Integer { return p.len }
type Team = { lead: Person, members: People }
```

## `empty` — zero values

`empty T` evaluates to the zero value of `T`: a struct with all fields zeroed,
an empty array, `0`/`false`, an empty string.

```x
let nobody = empty Person       // { name: "", age: 0 }
let blank  = empty People       // an empty array (len 0)
let zeroed = empty Team         // nested: members is an empty array too
```

It is a concrete blank value, distinct from an optional's `none`. Note it
**bypasses refined-type checks** (a zero may not satisfy a constraint), so treat
it as a deliberate blank/null-object, not a validated value.

## Function kinds

Intent is part of the syntax. Each kind documents purity and effect:

| Kind | Meaning |
|------|---------|
| `mapper` | `T -> U` pure transformation |
| `projector` | structural field extraction |
| `predicate` | `T -> Bool` |
| `consumer` | side-effecting; may mutate |
| `producer` | `() -> T` (often I/O) |
| `reducer` | `(Acc, T) -> Acc` |
| `creator` | constructs instances |
| `action` | impure; may mutate; not a pure function (e.g. a web `handle`) |

```x
mapper fullName(p: Person) -> String { return p.name }
predicate isAdult(p: Person) { return p.age >= 18 }
consumer log(msg: String) { system.stdout.writeln(msg) }
```

> **Purity is enforced.** `mapper`, `predicate`, and `projector` are pure: the
> compiler rejects a body that does I/O (`system.stdout`/`stderr`/`stdin`) or
> calls an effectful function (a `consumer` or `action`). If a function needs a
> side effect, give it an effectful kind — usually `producer` (effect + returns a
> value) or `consumer`/`action`. This isn't bookkeeping for its own sake: the
> guarantee is what lets the compiler treat a pure function's arguments as
> borrowed (no copy, no reference-count traffic). Calls into
> `extern "C"` functions are trusted at their declared kind, and calling a
> `producer`/`creator` from a pure function is allowed (constructing or producing
> a value is not a side effect on the caller's inputs).

A one-expression body can be written **inline** with `=>` — sugar for
`{ return <expr> }` (bounded to its line; use a `{ block }` for multi-line). It
works for any kind, including methods and `where`-overloads:

```x
mapper   fullName(p: Person) -> String => p.first + " " + p.last
predicate isAdult(p: Person)            => p.age >= 18
mapper   tier(n: Integer) -> String where n >= 100 => "high"
mapper   tier(n: Integer) -> String                => "low"
```

## First-class functions (closures)

A **lambda** `(p: T) => expr` is a *value* of function type `(T) -> U`. Bind it,
call it, and pass it to higher-order functions:

```x
let inc = (n: Integer) => n + 1          // value of type (Integer) -> Integer
inc(41)                                   // 42

producer apply(f: (Integer) -> Integer, x: Integer) -> Integer { return f(x) }
apply((n: Integer) => n * 3, 5)           // 15

// a predicate value passed in and applied
producer keep(xs: Integer[], p: (Integer) -> Bool) -> Integer {
    let n = 0
    for x in xs { if p(x) { n = n + 1 } }
    return n
}
keep([1, 5, 2, 9], (n: Integer) => n > 3) // 2
```

A lambda lowers to a top-level function plus a captured-environment pointer (no
boxing, no GC). Current scope:

- **One parameter**, written with its **type** (`(n: Integer) => …`).
- **Capture-free**: the body sees only its own parameter, not the enclosing
  scope's locals (referencing them is a compile error). Pass what it needs as an
  argument.
- The body's result type must **match** the declared `-> U` of the function-typed
  parameter it's passed to.

Multi-parameter lambdas, captures, and generics are the next steps (see the
feature matrix in `FEATURES.md`). See `examples/closures_demo.xi`.

## Concurrency: `async` / `await`

An **`async` function** runs on its own worker thread when called and returns a
`Future<T>` **immediately** — the caller keeps going while the work proceeds in
the background. `await` blocks until the result is ready and yields the `T`. The
`async` keyword is what makes a call spawn; the body returns the plain `T`:

```x
async producer work(n: Integer) -> Integer {   // call yields Future<Integer>
    return n * n
}

let f = work(6)        // starts the worker, returns a Future<Integer> now
let r = await f        // 36 — blocks here until the worker finishes
```

A `-> Future<T>` **return type** (without `async`) means the function *returns a
future value it built* — it is **not** auto-spawned. Use it for helpers that
forward or combine futures:

```x
producer (logger: Logger) ping(name: String, ms: Integer) -> Future<Integer> {
    return runWithDelay(ms) { logger.info("ping " + name) }   // returns the future
}
```

**`await all`** joins a `List<Future<T>>` and returns a `List<T>`, in order.
Spawn the calls first so they run concurrently, then await them together:

```x
let jobs = listOf(work(2), work(3), work(4))   // three workers start here
let done = await all jobs                       // List<Integer> = [4, 9, 16]
```

Three 100ms jobs finish in ~100ms, not 300ms — they run in parallel.

### `runWithDelay` — run a block after a delay

`runWithDelay(ms) { … }` runs a block on a worker thread after `ms`
milliseconds and returns a `Future` immediately, so it is `await`-able like any
other:

```x
let f = runWithDelay(1000) { logger.info("yo") }   // fires in 1s; returns now
// ... do other work ...
await f                                              // wait for it to finish
```

The block **captures** the enclosing function's parameters and dependencies by
value (here `logger`), so it can use them on the worker. It cannot reference
locals declared earlier in the same body — pass those in via a wrapping
function. See `examples/delay_demo.xi`.

### Notes

- **Memory:** a future's worker allocates-and-leaks (it does **not** use a
  per-thread arena), so the result — and everything it points to (a `String`,
  a struct, a `List`) — safely outlives the `await`. See
  [Memory management](memory.md).
- **Purity still applies:** an `async mapper`/`predicate` may not do I/O; use
  `async producer`/`consumer`/`action` for effectful background work.
- `async` on an **entry** (`async entry main`) and on interface/class **methods**
  is the established synchronous form and is unchanged — only free `async`
  functions spawn. See `examples/async_demo.xi`.

## Scheduled jobs — `scheduled … cron`

A `scheduled` job runs a block on a **cron schedule**. It declares its own
dependencies (auto-wired, exactly like a function or `entry`) and a 5-field cron
expression — `minute hour day-of-month month day-of-week`:

```x
scheduled (logger: Logger) greeter() cron "5 4 * * *" {   // 04:05 every day
    logger.info("test!")
}

scheduled (logger: Logger) heartbeat() cron "* * * * *" { logger.info("tick") }  // every minute
```

Cron fields accept `*`, a number (`5`), a range (`1-5`), a step (`*/15`,
`0-30/10`), and comma lists (`0,15,30,45`). Day-of-week is `0`–`6` (Sunday = 0).

Declaring any scheduled job makes the program **run a scheduler** that keeps the
process alive and fires each job (at minute resolution) when local time matches.
A program can be *only* scheduled jobs (no `entry` needed); if you also have an
`entry`, its body runs first for setup — don't `return` early or the process
exits before the scheduler starts. See `examples/scheduled_demo.xi`.

## Infix functions

Mark a two-argument function `infix` and it can be called in **infix position** —
`a f b` is sugar for `f(a, b)`. It's still an ordinary function, so the normal
`f(a, b)` call keeps working:

```x
infix mapper    plus(a: Integer, b: Integer) -> Integer { return a + b }
infix predicate divides(a: Integer, b: Integer)         { return b % a == 0 }

5 plus 3              // 8         — same as plus(5, 3)
2 plus 3 plus 4       // 9         — left-associative
plus(10, 20)          // 30        — the function form still works
if 3 divides 12 { … } // an infix predicate reads well in a guard
```

Infix functions bind at low precedence (looser than arithmetic, like `to`), so
`a plus b * c` is `plus(a, b * c)`. Any function kind works (`mapper`,
`predicate`, `creator`, …); the `infix` modifier goes first, before `async` and
the kind. See `examples/infix_demo.xi`.

## `capture` — name a sub-expression's value

`EXPR capture name: Type` evaluates `EXPR`, binds its value to `name` (of the
given type), and the expression still **yields that value**. The binding lives
for the rest of the enclosing function, so you can use a call's result later even
when the call is buried inside a larger expression:

```x
let bigger = foo(10) capture a: Integer > bar(10) capture b: Integer
// bigger = foo(10) > bar(10);  a = 20, b = 11 are now in scope

if positive(make(7) capture box: Box) {
    use(box.v)              // the struct captured mid-call is reusable here
}
```

The type annotation is required (it's how the binding is declared). A captured
name is **zero-initialized**, so if its `capture` sits on a short-circuited
branch (the unevaluated side of `and`/`or`) it simply holds the zero value rather
than crashing. See `examples/capture_demo.xi`.

## `where`-guarded overloading

A function may be declared several times under the same name, each with a
`where` guard over its parameters. At a call site the compiler emits a dispatcher
that evaluates the guards **in declaration order** and calls the first match. An
unguarded overload is the default; if none matches and there is no default, the
program panics.

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

The same applies to **methods**: a class may declare a method several times with
`where` guards (each can use `self`/deps), and the first matching guard wins.
`std/web` routing is exactly this — several
`action handle(req, res) where req.path == "…"` overloads plus a default.

## Classes, deps, and dependency injection

Classes never extend classes; reuse is via interfaces and injected deps.
**Dependency injection is automatic**: the compiler discovers which class
implements each interface and wires it in — no registration required.

```x
interface Greeter   { mapper greet(u: User) -> String }
interface Formatter { mapper format(name: String) -> String }

class TieredGreeter implements Greeter {
    deps { logger: Logger, formatter: Formatter }   // auto-wired
    mapper greet(u: User) -> String { return formatter.format(u.name) }
}

async entry main(args: String[]) -> Integer {
    let greeter = App.resolve(Greeter)   // resolved automatically
    ...
}

module App {}   // empty — present only so `App.resolve` has a name to call
```

An interface method may carry a **default implementation** — a `{ … }` body that
implementors inherit unless they override it. The default runs over the method's
parameters (it can't touch instance fields, since the concrete type is unknown):

```x
interface WebRequestHandler {
    action handle(req: HttpRequest, res: HttpResponse)
    mapper getBaseUrl() -> String { return "/" }   // default; override to mount elsewhere
}
```

### Steering with `bind` (optional)

A `module` may `bind` an interface to a specific class, or mark a class as a
`singleton` (one shared instance) instead of the default `transient`
(constructed per dependent). Binds are **overrides** — only needed to pick among
candidates or change scope.

```x
module App {
    bind Logger  -> ConsoleLogger as singleton   // shared
    bind Greeter -> TieredGreeter as transient    // override the auto choice
}
```

### Disambiguating multiple implementations

When an interface has more than one implementation, a dependency says which one
it wants:

```x
class TaxEngine implements Engine {
    deps {
        logger: Logger                              // exactly one impl -> auto
        calc:   Calculator where calc.precise()      // pick the impl whose guard holds
        rules:  TaxRule[]                            // inject ALL implementations
        repo:   Repository or EmptyRepository        // use a real Repository, else the fallback
    }
}
```

| Form | Meaning |
|------|---------|
| `d: I` | the single implementation of `I` (or the bound one) |
| `d: I where <cond>` | among `I`'s implementations, the first whose `<cond>` (over `d`) holds |
| `d: I[]` | an array of **all** implementations of `I` |
| `d: I or J` | the resolved `I`, or class `J` if none qualifies |
| `d: I?` | the implementation if one exists, else `none` |

### Function-, method-, and entry-level dependencies

A function, method, or `entry` can declare its own deps between the kind and the
name; they are auto-resolved before the body and visible by name. Use `(…)` for
plain deps and `{…}` when you need disambiguation (`where` / `or` / `I[]` / `I?`):

```x
mapper (logger: Logger) mapPerson(p: Person) -> ResponseDTO {      // simple: ( )
    logger.print("mapping " + p.name)
    return ResponseDTO { greeting: "Hello, " + p.name }
}

mapper { db: Repo where env == "prod" } load(id: String) -> Row { ... }   // guarded: { }

async entry (logger: Logger) main(args: String[]) -> Integer {     // entry too
    logger.print("Hello, world!")
    return 0
}
```

Interface calls dispatch through a vtable; the compiler devirtualizes when the
concrete type is known. See the dedicated [Dependency injection](dependency-injection.md)
page, plus `examples/di_auto.xi` and `examples/logger_demo.xi`.

## Control flow

```x
if isAdult(u) { ... } else { ... }

if let row = maybeRow { use(row) }       // optional unwrap

for item in items { ... }                // arrays, List<T>, Set<T>

for i in 1..5 { ... }                    // ranges: 1 2 3 4 5 (inclusive)
for i in 0 until 5 { ... }               // 0 1 2 3 4 (exclusive end)
for i in 10 downTo 1 { ... }             // counts down
for i in 0..100 step 10 { ... }          // custom stride

while cond { ... }

loop { ... }                             // forever; exit with `break` or `return`

for x in items {
    if skip(x) { continue }              // next iteration
    if done(x) { break }                 // leave the loop
}

match status {
    200 -> { return "ok" }
    404 -> { return "missing" }
    n   -> { return "other " + n }       // binds n
}
```

A `match` arm can be a `{ block }` or — as sugar — a single-line **inline
expression**, which is returned. Patterns may be a single key, a
**parenthesised list** of keys (matches any), or `else` / `_` for the default:

```x
match code {
    "x"                -> { return 345 }   // block arm
    "A"                -> 101              // inline: same as -> { return 101 }
    ("BA", "BD", "BR") -> 200             // multi-key: any of these
    else               -> 300             // default (alias for `_`)
}
```

(An inline arm is bounded to its line; use a `{ block }` for multi-line bodies.)

### Scopes and `unsafe`

```x
scope {
    let tmp = build()        // everything allocated here is freed when the
    use(tmp)                 // block ends — keeps long-running loops flat
}

unsafe {
    // escape hatch for low-level/FFI code the normal rules would reject
}
```

A `scope { }` block is a memory **region**: its allocations are reclaimed at the
end of the block (don't let a value escape it). See
[Memory management](memory.md). An `unsafe { }` block relaxes Xi's safety checks
for interop-heavy code — see [C interop](ffi.md).

See [Error handling](error-handling.md) for `T!`, `?`, `ok`/`err`, and
[Multi-file projects](multi-file.md) for `import`/`namespace`.
