# Language guide

## Primitive types

`Number` (f64), `Integer` (i64), `Bool`, `String`, `Char`, `Timestamp`, `Size`,
`Void`.

## Strings

A plain string is double-quoted and carries the usual escapes (`\n`, `\t`, `\"`,
`\\`):

```x
let s = "tab\tand\nnewline"
```

A **triple-quoted** string spans multiple lines. A single leading newline (right
after the opening `"""`) is dropped, and the common leading indentation shared by
all non-blank lines is stripped - so the block can sit at the indentation of the
surrounding code without that indentation leaking into the value:

```x
let msg = """
    Dear user,
      thanks for trying Ξ.
    - the team"""
// == "Dear user,\n  thanks for trying Ξ.\n- the team"
```

**Interpolation** is opt-in: prefix a string with `$` and `${expr}` holes are
evaluated and concatenated (scalars coerce to text). It works on both single-line
and triple-quoted strings. A plain string is never interpolated, so `${...}` stays
literal - handy for shell commands and other text that uses that syntax.

```x
let name = "Ada"
let age  = 36
let one  = $"Hello ${name}, you are ${age}"      // "Hello Ada, you are 36"
let calc = $"next year: ${age + 1}"              // "next year: 37"
let card = $"""
    Name: ${name}
    Age:  ${age}"""                              // indent-stripped + filled
let raw  = "path is ${HOME}/bin"                 // literal - not interpolated
```

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
Deconstruct with `match` - a variant pattern may bind the payload:

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

Sum types may be **recursive** - a variant's payload can reference the
enclosing sum type directly or through a container, so trees are ordinary
values:

```x
type Expr =
    | Lit  { value: Integer }
    | Add  { left: Expr, right: Expr }        // direct recursion (auto-boxed)
    | Call { name: String, args: List<Expr> } // recursion through a container

mapper eval(e: Expr) -> Integer {
    match e {
        Lit l  -> { return l.value }
        Add a  -> { return eval(a.left) + eval(a.right) }
        Call c -> { let s = 0  for x in c.args { s = s + eval(x) }  return s }
    }
    return 0
}
```

Directly self-referential fields are stored boxed behind the scenes;
construction and field access are unchanged. Recursive values also serialize -
see [serialization](serialization.md).

## Type aliases

A `type` can alias another type - handy for readable *plural* names for arrays:

```x
type Person = { name: String, age: Number }
type People = Person[]          // plural alias for an array
type Name   = String            // plain alias

mapper headcount(p: People) -> Integer { return p.len }
type Team = { lead: Person, members: People }
```

## `empty` - zero values

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
> side effect, give it an effectful kind - usually `producer` (effect + returns a
> value) or `consumer`/`action`. This isn't bookkeeping for its own sake: the
> guarantee is what lets the compiler treat a pure function's arguments as
> borrowed (no copy, no reference-count traffic). Calls into
> `extern "C"` functions are trusted at their declared kind, and calling a
> `producer`/`creator` from a pure function is allowed (constructing or producing
> a value is not a side effect on the caller's inputs).

A one-expression body can be written **inline** with `=>` - sugar for
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
feature matrix in `FEATURES.md`). See `examples/language/closures_demo.xi`.

## Concurrency: `async` / `await`

An **`async` function** runs on its own worker thread when called and returns a
`Future<T>` **immediately** - the caller keeps going while the work proceeds in
the background. `await` blocks until the result is ready and yields the `T`. The
`async` keyword is what makes a call spawn; the body returns the plain `T`:

```x
async producer work(n: Integer) -> Integer {   // call yields Future<Integer>
    return n * n
}

let f = work(6)        // starts the worker, returns a Future<Integer> now
let r = await f        // 36 - blocks here until the worker finishes
```

A `-> Future<T>` **return type** (without `async`) means the function *returns a
future value it built* - it is **not** auto-spawned. Use it for helpers that
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

Three 100ms jobs finish in ~100ms, not 300ms - they run in parallel.

### `runWithDelay` - run a block after a delay

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
locals declared earlier in the same body - pass those in via a wrapping
function. See `examples/concurrency/delay_demo.xi`.

### Notes

- **Memory:** a future's worker allocates-and-leaks (it does **not** use a
  per-thread arena), so the result - and everything it points to (a `String`,
  a struct, a `List`) - safely outlives the `await`. See
  [Memory management](memory.md).
- **Purity still applies:** an `async mapper`/`predicate` may not do I/O; use
  `async producer`/`consumer`/`action` for effectful background work.
- `async` on an **entry** (`async entry main`) and on interface/class **methods**
  is the established synchronous form and is unchanged - only free `async`
  functions spawn. See `examples/concurrency/async_demo.xi`.

## Scheduled jobs - `scheduled … cron` / `every`

A `scheduled` job runs a block on a schedule. It declares its own dependencies
(auto-wired, exactly like a function or `entry`) and either a 5-field **cron**
expression - `minute hour day-of-month month day-of-week` - or a fixed
**millisecond interval** with `every <N>ms`:

```x
scheduled (logger: Logger) greeter() cron "5 4 * * *" {   // 04:05 every day
    logger.info("test!")
}

scheduled (logger: Logger) heartbeat() cron "* * * * *" { logger.info("tick") }  // every minute

scheduled (logger: Logger) poll() every 5000ms {          // every 5 seconds
    logger.info("polling")
}
```

Cron fields accept `*`, a number (`5`), a range (`1-5`), a step (`*/15`,
`0-30/10`), and comma lists (`0,15,30,45`). Day-of-week is `0`–`6` (Sunday = 0).
The `every <N>ms` form fires every `N` milliseconds (the `ms` unit is optional;
sub-second intervals are honored, unlike cron's minute resolution).

Declaring any scheduled job makes the program **run a scheduler** that keeps the
process alive and fires each job (at minute resolution) when local time matches.
A program can be *only* scheduled jobs (no `entry` needed); if you also have an
`entry`, its body runs first for setup - don't `return` early or the process
exits before the scheduler starts. See `examples/concurrency/scheduled_demo.xi`.

## Infix functions

Mark a two-argument function `infix` and it can be called in **infix position** -
`a f b` is sugar for `f(a, b)`. It's still an ordinary function, so the normal
`f(a, b)` call keeps working:

```x
infix mapper    plus(a: Integer, b: Integer) -> Integer { return a + b }
infix predicate divides(a: Integer, b: Integer)         { return b % a == 0 }

5 plus 3              // 8         - same as plus(5, 3)
2 plus 3 plus 4       // 9         - left-associative
plus(10, 20)          // 30        - the function form still works
if 3 divides 12 { … } // an infix predicate reads well in a guard
```

Infix functions bind at low precedence (looser than arithmetic, like `to`), so
`a plus b * c` is `plus(a, b * c)`. Any function kind works (`mapper`,
`predicate`, `creator`, …); the `infix` modifier goes first, before `async` and
the kind. See `examples/language/infix_demo.xi`.

## Extension functions - `mapper Type.method(...)`

Add a method to **any type** - a primitive or your own - by qualifying the name
with the receiver type. Inside the body, `this` is the receiver:

```x
mapper Integer.double() -> Integer => this * 2

type Person = { name: String, family: String }
mapper Person.fullName() -> String { return this.name + " " + this.family }

let n = 21
n.double()                                  // 42
Person { name: "Ada", family: "Lovelace" }.fullName()   // "Ada Lovelace"
```

Call them with the usual `receiver.method(args)` syntax. Extensions take regular
parameters after the receiver, return like any function, and **chain**
(`n.double().plus(1)`). Any function kind works (`mapper`, `predicate`, …). They
desugar to a plain function taking the receiver as a `this` parameter, so there's
no runtime cost.

The receiver may also be an **array type** - `Type[].method` - with `this` the
array:

```x
mapper Integer[].total() -> Integer {
    let s = 0
    for x in this.data { s = s + x }
    return s
}
[3, 4, 5].total()      // 12
```

See `examples/language/extensions_test.xi`.

## `capture` - name a sub-expression's value

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
than crashing. See `examples/language/capture_demo.xi`.

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
`where` guards (each can use `this`/deps), and the first matching guard wins.
`std/web` routing is exactly this - several
`action handle(req, res) where req.path == "…"` overloads plus a default.

## Classes, deps, and dependency injection

Classes never extend classes; reuse is via interfaces and injected deps.
**Dependency injection is automatic**: the compiler discovers which class
implements each interface and wires it in - no registration required.

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

module App {}   // empty - present only so `App.resolve` has a name to call
```

An interface method may carry a **default implementation** - a `{ … }` body that
implementors inherit unless they override it. The default runs over the method's
parameters (it can't touch instance fields, since the concrete type is unknown):

```x
interface WebRequestHandler {
    action handle(req: HttpRequest, res: HttpResponse)
    mapper getBaseUrl() -> String { return "/" }   // default; override to mount elsewhere
}
```

### Generics

An interface may take **type parameters** in angle brackets, making it a
template a class fills in when it implements a concrete instantiation:

```x
interface Repository<TKey, TEntity> {
    producer findById(id: TKey) -> TEntity?
    consumer save(e: TEntity)
}

class UserRepo implements Repository<Integer, User> {
    deps {}
    producer findById(id: Integer) -> User? { … }
    consumer save(e: User) { … }
}
```

Type parameters appear anywhere a type does - parameters, return types, and the
arguments of an interface a template `extends`. A generic interface resolves by
**monomorphization**: for each concrete `implements Repository<Integer, User>`,
the compiler synthesizes a non-generic interface with the parameters
substituted, so vtables, casters, and dependency injection (including resolving
a generic interface from a class's `deps`) all work unchanged. Interfaces the
template `extends` are flattened into the concrete interface as well.

A generic interface's **default methods** are *materialized* into each
implementing class: an un-overridden default is copied (type-substituted) into
your class, so its body can call sibling methods on `this` - which is how a
repository's default `findById` calls `findAll`, and `findAll` calls
`getProvider`. Supply only the methods left abstract; override any default.

The standard [`Repository` / `CrudRepository`](data.md) interfaces are built this
way.

### Steering with `bind` (optional)

A `module` may `bind` an interface to a specific class, or mark a class as a
`singleton` (one shared instance) instead of the default `transient`
(constructed per dependent). Binds are **overrides** - only needed to pick among
candidates or change scope.

```x
module App {
    bind Logger  -> ConsoleLogger as singleton   // shared
    bind Greeter -> TieredGreeter as transient    // override the auto choice
}
```

### Mutable class state

Alongside its injected `deps`, a class may hold **mutable instance data** in a
`state { … }` block. Fields are read and written through `this.field`, and each
gets its initial value when the instance is constructed. Lifetime follows the DI
scope: a `singleton` keeps its state across calls; `transient`/`scoped` start
fresh.

```x
interface Store { consumer bump()  projector count() -> Integer }

class Counter implements Store {
    deps {}
    state { n: Integer = 0 }                // mutable instance data
    consumer bump()          { this.n = this.n + 1 }
    projector count() -> Integer => this.n
}

module App { bind Store -> Counter as singleton }
```

Reach for `state` when a service genuinely accumulates (a cache, counter, pool);
for shared, event-sourced state prefer an [atom](machines.md). `this.field` also
reads an injected dep (`this.logger`).

A state field may hold a [machine](machines.md) value (machines are immutable
value types), letting a class own and drive a state machine - reassign the field
with each transition's result:

```x
class Gate implements ... {
    deps {}
    state { t: Turnstile = Turnstile.start() }
    consumer insertCoin() { this.t = this.t.coin() }   // transition -> new value
    projector state() -> String => this.t.state
}
```

### Module-scoped constants

A `module` may declare **`const` values** - immutable named values usable from
anywhere as `Module.NAME` (free functions, class methods, other modules). The
initializer is any compile-time expression.

```x
module App {
    const MAX_RETRIES: Integer = 3
    const APP_NAME: String     = "xi"
}

mapper capped(n: Integer) -> Integer {
    if n > App.MAX_RETRIES { return App.MAX_RETRIES }
    return n
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
page, plus `examples/di/di_auto.xi` and `examples/di/logger_demo.xi`.

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

A `match` arm can be a `{ block }` or - as sugar - a single-line **inline
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
    use(tmp)                 // block ends - keeps long-running loops flat
}

unsafe {
    // escape hatch for low-level/FFI code the normal rules would reject
}
```

A `scope { }` block is a memory **region**: its allocations are reclaimed at the
end of the block (don't let a value escape it). See
[Memory management](memory.md). An `unsafe { }` block relaxes Xi's safety checks
for interop-heavy code - see [C interop](ffi.md).

See [Error handling](error-handling.md) for `T!`, `?`, `ok`/`err`, and
[Multi-file projects](multi-file.md) for `import`/`namespace`.
