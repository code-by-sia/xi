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
//
// ── Live reload ─────────────────────────────────────────────────────────────
// Inject `ApplicationConfig` and call `watch(file, topic)` to get a background
// watcher that publishes a `ConfigChanged { file }` event (std/events) whenever
// the file is edited — re-read the config in a `listener` to hot-reload:
//
//     async entry (cfg: ApplicationConfig) main(args: String[]) -> Integer {
//         cfg.watch("application.yaml", "config.changed")
//         let pump = Events.runAsync()
//         ...
//     }
//     class Reloader {
//         deps {}
//         listener onChange(e: ConfigChanged) on "config.changed" {
//             // e.file changed -> readConfig<...>(e.file) again
//         }
//     }
//
// The default `FileApplicationConfig` polls the file's mtime (~1s). Bind your own
// `ApplicationConfig` (e.g. an OS-native watcher, or a no-op in tests) to change it.

import "std/events.xi"

extern "C" {
    producer xstd_config_watch(file: String, topic: String)
}

// Emitted when a watched config file changes.
event ConfigChanged { file: String }

interface ApplicationConfig {
    producer watch(file: String, topic: String)
}

class FileApplicationConfig implements ApplicationConfig {
    deps {}
    producer watch(file: String, topic: String) {
        xstd_config_watch(file, topic)
    }
}
