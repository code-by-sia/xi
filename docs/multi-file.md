# Multi-file projects

Large programs span multiple files using `import` and `namespace`.

## `import`

`import "relative/path.xi"` at the top level splices another file's declarations
into the compilation unit. Imports are resolved **recursively** and
**de-duplicated** by path, so a diamond of imports includes each file once.
Paths are relative to the importing file.

```x title="math.xi"
namespace math
mapper add(a: Number, b: Number) -> Number { return a + b }
mapper square(x: Number) -> Number { return x * x }
```

```x title="text.xi"
namespace text
mapper shout(s: String) -> String { return s + "!" }
```

```x title="main.xi"
import "math.xi"
import "text.xi"
import "std/log.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.info(text.shout("hello multi-file"))
    logger.info("2 + 3 = " + math.add(2, 3))
    logger.info("4^2 = "  + math.square(4))
    return 0
}
```

```console
$ xc main.xi && ./build/main
hello multi-file!
2 + 3 = 5
4^2 = 16
```

## `namespace`

`namespace a.b` prefixes a file's **top-level** names (e.g. `math.add` becomes
the symbol `math__add`) so independently authored files can reuse short names
without colliding. Reference a namespaced name from another file with its
qualified form `a.b.Name`, which the compiler resolves to the prefixed symbol.

- Method names and field accesses are **not** namespaced (so interface/vtable
  dispatch is unaffected) - only top-level declarations are.
- Two files can each define a `fmt` without conflict:

```x
// a.xi         namespace a   mapper fmt(s: String) -> String { return "[A]" + s }
// b.xi         namespace b   mapper fmt(s: String) -> String { return "[B]" + s }
// main.xi      import "a.xi"  import "b.xi"
//             a.fmt("one")  ->  [A]one
//             b.fmt("two")  ->  [B]two
```

## A manifest entry file

A common layout is one small entry file that imports the rest of the project:

```x title="app.xi"
import "models.xi"
import "repository.xi"
import "service.xi"

async entry (svc: Service) main(args: String[]) -> Integer {
    svc.run()
    return 0
}

module App {}
```

```console
$ xc app.xi && ./build/app
```

`import` merges all the parts into one compilation unit (recursively, with
duplicates resolved once), so you compile just the entry file.

## Module source sets (`includes` / `excludes`) {#module-source-sets-includes-excludes}

Instead of listing every `import`, a `module` can declare which files belong to
it with `includes` / `excludes` globs. When set, `xc <entry.xi>` gathers every
matching `.xi` file under the entry's directory and compiles them as one unit.
Each module owns its `entry main`, so **several modules can live in one folder and
build separately**:

```x title="server.xi"
import "std/log.xi"
async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.info(banner("server"))      // banner() comes from shared.xi, auto-gathered
    return 0
}
module App {
    id       = "server"
    includes = ["./**"]                 // default: every .xi under this dir
    excludes = ["client.xi"]            // ...but not the other module's entry
}
```

```x title="client.xi"
import "std/log.xi"
async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.info(banner("client"))
    return 0
}
module App { id = "client"  includes = ["./**"]  excludes = ["server.xi"] }
```

```console
$ xc server.xi && ./build/server     # gathers shared.xi, not client.xi
$ xc client.xi && ./build/client
```

- `includes` defaults to `["./**"]` (the whole directory tree) and `excludes` to
  `[]`. Globs: `**`/`dir/**` (subtree), `dir/*` (one level), `*.ext`, or an exact
  file/basename.
- The feature is **opt-in**: a module with neither field keeps the classic
  "entry file + its explicit `import`s" behavior.
- Combine with `id` (see [DI › module metadata](dependency-injection.md#module-metadata))
  to name each module's binary.

Build every module in a tree at once with `xc --all` - it finds each buildable
module (a file with an `entry` + a `module`) and builds it separately.

## Module fields

Everything a `module` block can contain:

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `id` | string | source filename | name of the compiled binary |
| `name` | string | - | display name (metadata) |
| `description` | string | - | description (metadata) |
| `version` | string | - | version (metadata) |
| `license` | string | - | license (metadata) |
| `includes` | string[] | `["./**"]` when set | globs of files that belong to this module |
| `excludes` | string[] | `[]` | globs to drop from the include set |
| `dependencies` | string[] | `[]` | URLs to source archives, fetched by `xi install` (see below) |
| `scope` | keyword | `transient` | default DI scope for the whole program ([DI](dependency-injection.md#a-module-wide-default)) |
| `maxRequestBytes` | number | `33554432` (32 MB) | largest request the built-in server buffers ([web](web.md)) |
| `jsonMaxDepth` | number | `200` | deepest JSON nesting accepted ([serialization](serialization.md)) |
| `bind I -> Impl [as singleton]` | - | auto | DI override / scope ([DI](dependency-injection.md)) |
| `bind I -> readConfig("file")` | - | - | config-backed binding ([config](config.md)) |
| `[async] entry [(deps)] main(...) { … }` | - | - | the module's entry point (may also be top-level) |

```x
module App {
    id          = "billing"
    name        = "Billing Service"
    version     = "1.4.0"
    license     = "Apache 2.0"
    includes    = ["./**"]
    excludes    = ["scratch/**"]

    scope           = singleton      // default DI scope for the program
    maxRequestBytes = 1048576        // 1 MB: this service takes no uploads
    jsonMaxDepth    = 64

    bind Clock  -> SystemClock as transient   // the exception to `scope`

    async entry (logger: Logger) main(args: String[]) -> Integer {
        logger.info("billing up")
        return 0
    }
}
```

`maxRequestBytes` and `jsonMaxDepth` set this service's runtime limits at build
time; the matching environment variables (`XI_MAX_REQUEST`, `XI_JSON_MAX_DEPTH`)
still override them at deploy time, so ops can retune without a rebuild. Both are
clamped either way - see [web limits](web.md#notes--limits).


The `entry` may live **inside** the module (as above) or stay at the top level
with a separate `module App { … }` block - both are supported. Putting it inside
keeps each module self-contained, which is what makes `xc --all` build a folder
of modules into one binary each.

The block may be named (`module App { … }`), anonymous (`module { … }`), or
`module Test { … }` (whose binds win under `xi test`).

## Dependencies (`dependencies` + `xi install`)

A module can declare third-party libraries as `dependencies` - a list of URLs to
**source archives** (a `.tar.gz` or `.zip`, e.g. a GitHub release tarball):

```x title="server.xi"
import "std/log.xi"

module App {
    id           = "server"
    includes     = ["./main/**"]
    dependencies = ["https://github.com/code-by-sia/xi-sqlite/archive/refs/tags/v0.1.0.tar.gz"]

    async entry (logger: Logger) main(args: String[]) {
        logger.info(sqlite.version())     // a function from the dependency
    }
}
```

```console
$ xi install server.xi      # download + extract each dependency into ./modules
  fetching https://github.com/code-by-sia/xi-sqlite/archive/refs/tags/v0.1.0.tar.gz
xi install: 1/1 fetched into ./modules
$ xc server.xi && ./build/server
```

- **`xi install [file]`** downloads every dependency archive and extracts it into
  a `modules/` directory beside your project (`.tar.gz`/`.tgz` via `tar`, `.zip`
  via `unzip`). With no file, it installs the dependencies of every buildable
  module it finds. Needs `curl` (and `unzip` for `.zip`) on `PATH`.
- **At build time** `xc` automatically folds `modules/**` into the source gather,
  so installed libraries compile in with **no extra `import`** - reference their
  functions by their `namespace` (e.g. `sqlite.version()`). Commit `modules/` or
  re-run `xi install`, your choice - it's just source.
- A dependency is **plain Xi source**: a library should use a `namespace` and
  must not declare its own `entry`/`module` (those are for applications).

> Dependencies are fetched over the network and compiled into your program -
> only depend on archives you trust.

## Publishing a library (`library` + `xi pack`)

To share code, give the project a **`library` manifest** and package it with
`xi pack`. A `library { … }` block carries the library's identity (id, version,
metadata) and its source globs. Unlike `module`, it produces **no binary and is
inert when consumed** - so it can sit right next to the library's own code
without leaking an `entry`/`module` into the programs that depend on it:

```x title="greet.xi"
namespace greet

mapper hello(name: String) -> String { return "Hello, " + name + "!" }
mapper shout(s: String) -> String    { return s + "!!!" }

library {
    id       = "greet"
    name     = "Greet"
    version  = "1.2.0"
    license  = "Apache 2.0"
    includes = ["./**"]               // which files belong to the library
    excludes = ["**/*_test.xi"]
}
```

```console
$ xi pack                              # or: xi pack greet.xi
xi pack: wrote dist/greet-1.2.0.tar.gz  (1 files, library greet 1.2.0)
```

`xi pack` gathers the files matching `includes`/`excludes` and writes a source
archive `dist/<id>-<version>.tar.gz`. With no argument it finds the project's
`library` block automatically. (`build/`, `dist/`, and `modules/` are never
packed.)

Publish that tarball anywhere downloadable - a GitHub release is the natural
home - and consumers add its URL to their `dependencies` and run `xi install`:

```x title="app.xi (the consumer)"
module App {
    id           = "app"
    dependencies = ["https://github.com/you/greet/releases/download/v1.2.0/greet-1.2.0.tar.gz"]
}
```

```console
$ xi install        # extracts greet into ./modules
$ xc app.xi         # greet.hello(...) is now available, no extra import
```

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `id` | string | source filename | archive/library name |
| `name` / `version` / `license` / `description` | string | - | metadata |
| `includes` | string[] | `["./**"]` | globs of files to pack |
| `excludes` | string[] | `[]` | globs to drop |
