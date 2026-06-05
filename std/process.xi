// std/process — environment & subprocesses.  import "std/process.xi" then proc.env("HOME")
namespace proc

extern "C" {
    mapper   get_env(name: String, dflt: String) -> String
    mapper   run_command(cmd: String) -> Integer
    consumer xstd_exit(code: Integer)
}

mapper env(name: String) -> String { return get_env(name, "") }
mapper envOr(name: String, dflt: String) -> String { return get_env(name, dflt) }
mapper run(cmd: String) -> Integer { return run_command(cmd) }
consumer exit(code: Integer) { xstd_exit(code) }
