// std/config — typed configuration.  import "std/config.xi"
//
// Declare an interface describing your config, then bind it to a file with
// `readConfig`. The compiler synthesizes an implementor that loads the file once
// (a singleton) and deserializes each method's return value from the matching
// top-level key — primitives directly, compounds via the derived JSON codec.
// YAML and JSON are both supported (chosen by file extension).
//
//     type TaxConfig = { percent: Number, rate: Integer }
//
//     interface AppConfig {
//         mapper projectName() -> String      // reads the `projectName` key
//         mapper tax() -> TaxConfig           // reads + decodes the `tax` key
//     }
//
//     module App  { bind AppConfig -> readConfig("application.yaml") }
//     module Test { bind AppConfig -> readConfig("application-test.yaml") }
//
//     async entry (cfg: AppConfig) main(args: String[]) -> Integer {
//         system.stdout.writeln(cfg.projectName())
//         return 0
//     }
//
// A missing key yields the type's zero value.
//
// To read a single file into a value, use the generic form (format chosen by
// extension — JSON, YAML, or XML):
//
//     let tax = readConfig<TaxConfig>("tax.yaml")   // or .json / .xml
//
// `readConfig("file")` (no type arg) is recognized only as a `bind` target;
// `readConfig<T>("file")` is the generic value form.
