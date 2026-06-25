// Diag — the default Diagnostics: wraps the diag_* FFI (declared here, on top).
extern "C" {
    consumer diag_set_file(path: String)
    consumer diag_error(line: Integer, msg: String)
    consumer diag_warn(line: Integer, msg: String)
}

class Diag implements Diagnostics {
    deps {}
    consumer setFile(path: String) { diag_set_file(path) }
    consumer error(line: Integer, msg: String) { diag_error(line, msg) }
    consumer warn(line: Integer, msg: String) { diag_warn(line, msg) }
}
