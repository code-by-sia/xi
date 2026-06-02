# Showcase project

A small multi-file project (folder structure, one concern per file) that
exercises most of the language. `main.x` aggregates the imports; each module is
its own namespace.

```
showcase/
├── main.x                 entry: App.resolve, Result, match, stdlib
├── model/types.x          namespace model  — refined types, compound, creator
├── rules/classify.x       namespace rules  — where-guarded overloading
├── services/logger.x      namespace logging — interface + class
├── services/format.x      namespace format  — two impls (where-selected)
├── services/audit.x       namespace audit   — list-injected impls
├── services/greeter.x     namespace greet   — auto-DI deps (where + list)
└── util/parse.x           namespace util    — function-level deps + Result + `?`
```

| Feature | Where |
|---------|-------|
| refined types, compound, `creator`, `predicate` | `model/types.x` |
| constraint enforcement at construction | any `model.User { ... }` |
| `where`-guarded overloading | `rules/classify.x` |
| interfaces, classes, **automatic DI** | `services/*.x` |
| `where`-disambiguated dep, list (`audit.Rule[]`) dep | `services/greeter.x` |
| function-level deps, `Result` (`T!`), `?` | `util/parse.x` |
| `match`, stdlib (`text`, `convert`), cross-namespace refs | `main.x` |

## Run it

```console
$ export XC_RUNTIME="$PWD/runtime" XC_STD="$PWD"
$ ./compiler/xc examples/showcase/main.x   # -> build/main
$ ./build/main
[log] greeting Alice (2 audit rules)
Good day, Alice
ALICE is adult
[log] parsing age 42
42 -> age 42
[log] parsing age 999
999 -> age out of range: 999
[log] parsing age oops
oops -> not an integer: oops
two
```

`main.x` imports each module; sub-files reference other modules by their
namespace (e.g. `model.User`, `logging.Logger`). `XC_STD` points at the
directory containing `std/` so `import "std/..."` resolves.
