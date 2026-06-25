// Host — the platform the compiler runs on: file IO, environment, processes.
// An injectable service that wraps the side-effecting FFI (the extern block is
// declared in impl/ffi/host/posix_host.xi), so the orchestration code depends on
// this contract rather than on raw `extern "C"` calls.
interface Host {
    producer  readFile(path: String) -> String
    producer  writeFile(path: String, content: String) -> Bool
    predicate fileExists(path: String) -> Bool
    mapper    env(name: String, dflt: String) -> String
    mapper    setEnv(name: String, val: String) -> Integer
    mapper    exec(cmd: String) -> Integer
    producer  compileC(cpath: String, binpath: String) -> Integer
}
