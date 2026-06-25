// TokenArrays — growable typed-array primitives for Token[] and String[].
// Injectable wrapper over the array FFI; implemented by StdTokenArrays
// (impl/ffi/arrays/token_arrays.xi).
interface TokenArrays {
    mapper pushToken(arr: Token[], tok: Token) -> Token[]
    mapper tokenLen(arr: Token[]) -> Integer
    mapper tokenAt(arr: Token[], i: Integer) -> Token
    mapper pushString(arr: String[], s: String) -> String[]
    mapper stringLen(arr: String[]) -> Integer
    mapper stringAt(arr: String[], i: Integer) -> String
}
