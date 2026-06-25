// StdTokenArrays — the default TokenArrays: wraps the Token[]/String[] FFI.
extern "C" {
    mapper appendTokenC(arr: Token[], tok: Token) -> Token[]
    mapper tokenArrLen(arr: Token[]) -> Integer
    mapper tokenArrGet(arr: Token[], i: Integer) -> Token
    mapper appendString(arr: String[], s: String) -> String[]
    mapper stringArrLen(arr: String[]) -> Integer
    mapper stringArrGet(arr: String[], i: Integer) -> String
}

class StdTokenArrays implements TokenArrays {
    deps {}
    mapper pushToken(arr: Token[], tok: Token) -> Token[] { return appendTokenC(arr, tok) }
    mapper tokenLen(arr: Token[]) -> Integer { return tokenArrLen(arr) }
    mapper tokenAt(arr: Token[], i: Integer) -> Token { return tokenArrGet(arr, i) }
    mapper pushString(arr: String[], s: String) -> String[] { return appendString(arr, s) }
    mapper stringLen(arr: String[]) -> Integer { return stringArrLen(arr) }
    mapper stringAt(arr: String[], i: Integer) -> String { return stringArrGet(arr, i) }
}
