# Dependency injection & IoC

Ξ has **automatic dependency injection** built into the language. You program to
*interfaces*; the compiler discovers which class implements each interface and
wires it in. There's no container to configure, no framework, no annotations —
and it all resolves at compile time into plain vtable calls.

## The idea in one minute

*Inversion of control* means a component doesn't construct its collaborators; it
*declares what it needs* and receives them. The payoff:

- **Swap implementations** without touching callers (console logger → file
  logger → an in-memory buffer in tests).
- **Test in isolation** by injecting fakes.
- **No globals / singletons-by-hand** and no hidden construction order.

In Ξ the unit of substitution is an **interface**, and the wiring is automatic.

```x
import "std/log.xi"

interface Greeter { mapper greet(name: String) -> String }

class FriendlyGreeter implements Greeter {
    deps {}
    mapper greet(name: String) -> String => "Hey " + name + "!"
}

// Ask for the capabilities by interface; the compiler injects the implementors.
async entry (greeter: Greeter, logger: Logger) main(args: String[]) -> Integer {
    logger.info(greeter.greet("Ada"))
    return 0
}
```

No registration: `FriendlyGreeter` is the only `Greeter`, so it's chosen.

## Where dependencies are declared

| Site | Syntax |
|------|--------|
| **Class** (shared by all its methods) | `deps { repo: Repo, logger: Logger }` |
| **Function / method / `entry`** (simple) | `mapper (logger: Logger) f(x: T) -> U { … }` |
| **Function / method / `entry`** (with disambiguation) | `mapper { db: Repo where env == "prod" } f(...) { … }` |

The **`(…)` form** is for plain dependencies — the common case. The **`{…}` form**
additionally supports the disambiguation rules below (guards, lists, fallbacks).
A dependency is visible in the body by name and resolves before the body runs.

## Real-world patterns

### 1. A swappable Logger

The standard `Logger` (`std/log.xi`) is the canonical example. Inject it; the
default `ConsoleLogger` is used unless you bind another.

```x
import "std/log.xi"

class OrderService {
    deps { logger: Logger }
    consumer place(id: String) { logger.info("placing order " + id) }
}
```

Redirect every log line to a file or a test buffer by providing another
`Logger` implementor — `OrderService` doesn't change.

### 2. The repository pattern (swap the data source)

```x
interface UserRepo { mapper find(id: String) -> String }

class InMemoryUsers implements UserRepo {
    deps {}
    mapper find(id: String) -> String => "user:" + id
}

class ApiController {
    deps { users: UserRepo }                 // depends on the interface, not a DB
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/user" {
        res.send(User { name: users.find(req.query("id")) })
    }
}
```

Ship `InMemoryUsers` for dev/tests and a `PostgresUsers implements UserRepo` for
production; the controller is identical.

### 3. Services depending on services (a graph)

Dependencies compose transitively — the compiler resolves the whole graph.

```x
interface Clock  { mapper now() -> Integer }
interface Mailer { consumer send(to: String, body: String) }

class SystemClock implements Clock  { deps {} mapper now() -> Integer => time.nowMillis() }
class SmtpMailer  implements Mailer {
    deps { logger: Logger }                  // Mailer itself needs a Logger
    consumer send(to: String, body: String) { logger.print("mail " + to) }
}

class Billing {
    deps { clock: Clock, mailer: Mailer }    // gets both, fully wired
    consumer charge(user: String) { mailer.send(user, "charged at " + clock.now()) }
}
```

### 4. Testability — inject a fake

Because the collaborator is an interface, a test binds a stand-in:

```x
class FakeClock implements Clock { deps {} mapper now() -> Integer => 0 }

module Test { bind Clock -> FakeClock }      // deterministic time in tests
```

## Choosing among several implementations

When more than one class implements an interface, pick with a `module` binding or
let a dependency express its own rule (the `{…}` form):

```x
module App {
    bind Logger -> FileLogger as singleton   // one shared instance
    bind UserRepo -> PostgresUsers           // override the auto choice
}
```

| Rule | Meaning |
|------|---------|
| `dep: I` | the sole/auto-chosen implementor |
| `dep: I where <cond>` | pick the implementor for which the guard holds |
| `dep: I[]` | **all** implementors (a plugin list) |
| `dep: I or Fallback` | this impl, or `Fallback` if unavailable |
| `dep: I?` | optional — absent is allowed |

```x
interface Plugin { consumer run() }
class Compress implements Plugin { deps {} consumer run() { } }
class Encrypt  implements Plugin { deps {} consumer run() { } }

class Pipeline {
    deps { stages: Plugin[] }                // every Plugin, in declaration order
    consumer process() { for s in stages { s.run() } }
}
```

## Scopes

A binding is `transient` by default (constructed per dependent); mark it
`singleton` for one shared instance:

```x
module App { bind Cache -> LruCache as singleton }
```

Singletons live for the whole process (and are never freed by design); transients
are created where needed.

## Module metadata

The `module` block can also carry package metadata. `id` sets the **compiled
binary's name** (otherwise it's the source file name); `name`/`description`/
`version`/`license` are descriptive, and `includes`/`excludes` define the
module's source files (see [multi-file](multi-file.md#module-source-sets-includes-excludes)). The block may be named (`module App { … }`)
or anonymous (`module { … }`), and metadata can sit alongside `bind`s.

```x
module {
    id          = "file-server"     // -> binary named `file-server`
    name        = "File Server"
    description = "a simple file server"
    version     = "0.12"
    license     = "MIT"
}
```

There's no runtime container and no registration step — resolution is resolved at
compile time, so the abstraction is free at runtime.

See `examples/logger_demo.xi`, `examples/di_auto.xi`, and `examples/greeting.xi`.
