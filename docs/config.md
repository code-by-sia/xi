# Configuration

Typed configuration with zero boilerplate: describe your config as an
**interface**, bind it to a file with `readConfig`, and the compiler synthesizes
an implementor that loads the file once and deserializes each value.

```x
import "std/config.xi"

type TaxConfig = { percent: Number, rate: Integer }

interface AppConfig {
    mapper projectName() -> String      // reads the `projectName` key
    mapper tax() -> TaxConfig           // reads + decodes the `tax` key
    mapper flags() -> Flags
}

module App  { bind AppConfig -> readConfig("application.yaml") }
module Test { bind AppConfig -> readConfig("application-test.yaml") }
```

Inject it like any other dependency:

```x
async entry (cfg: AppConfig, logger: Logger) main(args: String[]) -> Integer {
    logger.info("project = " + cfg.projectName())
    logger.info("tax = " + number_to_str(cfg.tax().percent) + "%")
    return 0
}
```

```yaml
# application.yaml
projectName: Ledger
tax:
  percent: 20.0
  rate: 3
```

## How it works

- Each interface **method name maps to a top-level config key** (`tax()` → the
  `tax` key).
- The return type drives deserialization: **primitives** (`String`, `Number`,
  `Integer`, `Bool`) are read directly; **compound types** are decoded via the
  derived JSON codec (nested objects supported).
- The file is read **once** (a singleton) on first use.
- **YAML and JSON** are both supported, chosen by the file extension.
- A **missing key yields the type's zero value** (empty string, `0`, `false`,
  all-zero compound) — it never crashes.

## Test configuration

In a test build (`xi test`), a `bind` inside `module Test` **wins** over
`module App`, so tests transparently load a test config:

```x
module App  { bind AppConfig -> readConfig("application.yaml") }
module Test { bind AppConfig -> readConfig("application-test.yaml") }
```

See `examples/config_demo.xi`.

> `readConfig` is recognized by the compiler only as a `bind` target — it is not
> a callable function.
