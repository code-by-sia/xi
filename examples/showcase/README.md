# Showcase project

A small multi-file project (folder structure, one concern per file) that
exercises most of the language. `main.xi` aggregates the imports; each module is
its own namespace.

```
showcase/
├── main.xi                 entry: App.resolve, Result, match, stdlib
├── model/types.xi          namespace model  — refined types, compound, creator
├── rules/classify.xi       namespace rules  — where-guarded overloading
├── services/logger.xi      namespace logging — interface + class
├── services/format.xi      namespace format  — two impls (where-selected)
├── services/audit.xi       namespace audit   — list-injected impls
├── services/greeter.xi     namespace greet   — auto-DI deps (where + list)
└── util/parse.xi           namespace util    — function-level deps + Result + `?`
```

| Feature | Where |
|---------|-------|
| refined types, compound, `creator`, `predicate` | `model/types.xi` |
| constraint enforcement at construction | any `model.User { ... }` |
| `where`-guarded overloading | `rules/classify.xi` |
| interfaces, classes, **automatic DI** | `services/*.xi` |
| `where`-disambiguated dep, list (`audit.Rule[]`) dep | `services/greeter.xi` |
| function-level deps, `Result` (`T!`), `?` | `util/parse.xi` |
| `match`, stdlib (`text`, `convert`), cross-namespace refs | `main.xi` |

## Run it

```console
$ export XC_RUNTIME="$PWD/runtime" XC_STD="$PWD"
$ ./compiler/xc examples/showcase/main.xi   # -> build/main
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

`main.xi` imports each module; sub-files reference other modules by their
namespace (e.g. `model.User`, `logging.Logger`). `XC_STD` points at the
directory containing `std/` so `import "std/..."` resolves.
