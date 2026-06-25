// The `module` block carries package metadata. `id` becomes the compiled
// binary's name — so this builds to `build/file-server`, not `build/module_meta_demo`.
// `name`/`description`/`version`/`license` are descriptive metadata.
//
//   xc examples/module_meta_demo.xi && ./build/file-server
import "std/log.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    logger.info("file server starting")
    return 0
}

module {
    id          = "file-server"
    name        = "File Server"
    description = "a simple file server"
    version     = "0.12"
    license     = "Apache 2.0"
}
