// PosixHost — the default Host: thin wrappers over the platform FFI (declared
// here, on top). Method names differ from the externs they call (readFile vs
// file_read_all, ...) so a bare call resolves to the free extern, not to self.
extern "C" {
    predicate xstd_file_exists(path: String) -> Bool
    producer  file_read_all(path: String) -> String
    producer  file_write(path: String, content: String) -> Bool
    mapper    get_env(name: String, dflt: String) -> String
    mapper    set_env(name: String, val: String) -> Integer
    mapper    run_command(cmd: String) -> Integer
    producer  compile_c(cpath: String, binpath: String) -> Integer
}

class PosixHost implements Host {
    deps {}
    producer  readFile(path: String) -> String { return file_read_all(path) }
    producer  writeFile(path: String, content: String) -> Bool { return file_write(path, content) }
    predicate fileExists(path: String) -> Bool { return xstd_file_exists(path) }
    mapper    env(name: String, dflt: String) -> String { return get_env(name, dflt) }
    mapper    setEnv(name: String, val: String) -> Integer { return set_env(name, val) }
    mapper    exec(cmd: String) -> Integer { return run_command(cmd) }
    producer  compileC(cpath: String, binpath: String) -> Integer { return compile_c(cpath, binpath) }
}
