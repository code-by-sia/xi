// Diagnostics — error/warning reporting. An injectable service wrapping the
// diag_* FFI. Implemented by Diag (impl/ffi/diag/diagnostics.xi), where the extern
// block is declared.
interface Diagnostics {
    consumer setFile(path: String)
    consumer error(line: Integer, msg: String)
    consumer warn(line: Integer, msg: String)
}
