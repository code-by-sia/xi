// A shareable library. In its own project directory you'd run `xi pack`, which
// writes dist/greet-1.2.0.tar.gz — host that (e.g. a GitHub release) and other
// projects depend on the URL via `dependencies` + `xi install`.
//
// The `library` block declares identity + which files to pack. It produces no
// binary and is inert when this source is gathered into a consumer, so it can
// live right beside the library's own code. (`xi pack` packs the manifest's
// whole directory tree, so a real library lives in its own folder.)
namespace greet

mapper hello(name: String) -> String { return "Hello, " + name + "!" }
mapper shout(s: String) -> String    { return s + "!!!" }

library {
    id       = "greet"
    name     = "Greet"
    version  = "1.2.0"
    license  = "Apache 2.0"
    includes = ["./**"]
    excludes = ["**/*_test.xi"]
}
