# Multi-file projects

Large programs span multiple files using `import` and `namespace`.

## `import`

`import "relative/path.xi"` at the top level splices another file's declarations
into the compilation unit. Imports are resolved **recursively** and
**de-duplicated** by path, so a diamond of imports includes each file once.
Paths are relative to the importing file.

```x title="examples/proj/math.xi"
namespace math
mapper add(a: Number, b: Number) -> Number { return a + b }
mapper square(x: Number) -> Number { return x * x }
```

```x title="examples/proj/text.xi"
namespace text
mapper shout(s: String) -> String { return s + "!" }
```

```x title="examples/proj/main.xi"
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
$ ./compiler/xc examples/proj/main.xi && ./examples/proj/main
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
  dispatch is unaffected) — only top-level declarations are.
- Two files can each define a `fmt` without conflict:

```x
// a.xi         namespace a   mapper fmt(s: String) -> String { return "[A]" + s }
// b.xi         namespace b   mapper fmt(s: String) -> String { return "[B]" + s }
// main.xi      import "a.xi"  import "b.xi"
//             a.fmt("one")  ->  [A]one
//             b.fmt("two")  ->  [B]two
```

## The compiler itself is multi-file

The Xi compiler uses exactly this feature for its own source. `compiler/xc.xi` is
just a manifest:

```x
import "lexer.xi"
import "parser.xi"
import "codegen.xi"
import "driver.xi"
```

Building `./compiler/xc compiler/xc.xi` merges the four parts into one unit — the
same mechanism your projects use.
