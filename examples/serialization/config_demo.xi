// Typed configuration (std/config). Describe the config as an interface, then
// `bind` it to a file with `readConfig`. The compiler loads the file once and
// deserializes each method's value from the matching top-level key — primitives
// directly, compounds via the derived JSON codec. YAML and JSON both work.
//
// (the path is relative to where you run the binary; here, the repo root)
//   xc examples/config_demo.xi && ./build/config_demo
import "std/log.xi"
import "std/config.xi"
import "std/convert.xi"

type TaxConfig = { percent: Number, rate: Integer }
type Flags     = { calcTax: Bool, maxSalary: Number }

interface AppConfig {
    mapper projectName() -> String      // reads the `projectName` key
    mapper tax() -> TaxConfig           // reads + decodes the `tax` key
    mapper flags() -> Flags             // reads + decodes the `flags` key
}

async entry (cfg: AppConfig, logger: Logger) main(args: String[]) -> Integer {
    logger.info("project = " + cfg.projectName())
    let t = cfg.tax()
    logger.info("tax     = " + number_to_str(t.percent) + "% (rate " + int_to_string(t.rate) + ")")
    let f = cfg.flags()
    logger.info("flags   = calcTax " + f.calcTax + ", maxSalary " + number_to_str(f.maxSalary))
    return 0
}

module App  { bind AppConfig -> readConfig("examples/config_demo.yaml") }
// In tests, `module Test { bind AppConfig -> readConfig("...-test.yaml") }` wins.
