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

It lowers to one implementation per overload plus a dispatcher:

```c
static xc_string_t xc_mapResponse(xc_ApiResponse_t res) {
    if ((res.status == 200LL)) return xc_mapResponse__ovl0(res);
    if ((res.status == 404LL)) return xc_mapResponse__ovl1(res);
    if ((res.status >= 500LL)) return xc_mapResponse__ovl2(res);
    return xc_mapResponse__ovl3(res);
}
```

The same applies to **methods**: a class may declare a method several times with
`where` guards (each can use `self`/deps), and the compiler builds a per-method
dispatcher behind its interface slot. `std/web` routing is exactly this — several
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

### Function-level dependencies

A function can declare its own deps in a block between the kind and the name;
they are auto-resolved on entry and visible in the body:

```x
mapper { logger: Logger } mapPerson(p: Person) -> ResponseDTO {
    logger.log("mapping " + p.name)
    return ResponseDTO { greeting: "Hello, " + p.name }
}
```

Interface calls dispatch through a vtable; the compiler devirtualizes when the
concrete type is known. See `examples/di_auto.xi`.

## Control flow

```x
if isAdult(u) { ... } else { ... }

if let row = maybeRow { use(row) }       // optional unwrap

for item in items { ... }                // arrays

while cond { ... }

match status {
    200 -> { return "ok" }
    404 -> { return "missing" }
    n   -> { return "other " + n }       // binds n
}
```

See [Error handling](error-handling.md) for `T!`, `?`, `ok`/`err`, and
[Multi-file projects](multi-file.md) for `import`/`namespace`.
