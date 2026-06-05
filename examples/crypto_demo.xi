// std/crypto — hashing, HMAC, encodings, and secure random (no external libs).
import "std/crypto.xi"
import "std/bytes.xi"

async entry main(args: String[]) -> Integer {
    // hashes (hex digests of a string)
    system.stdout.writeln("sha256 = " + crypto.sha256Hex("the Xi language"))
    system.stdout.writeln("sha1   = " + crypto.sha1Hex("the Xi language"))
    system.stdout.writeln("md5    = " + crypto.md5Hex("the Xi language"))

    // HMAC-SHA256 (e.g. signing an API token)
    system.stdout.writeln("hmac   = " + crypto.hmacSha256Hex("secret-key", "message"))

    // encodings
    let raw = bytes.fromString("hello, Xi")
    let b64 = crypto.base64(raw)
    system.stdout.writeln("base64 = " + b64)
    system.stdout.writeln("back   = " + bytes.toString(crypto.fromBase64(b64)))
    system.stdout.writeln("hex    = " + crypto.hex(raw))

    // a fresh random token
    system.stdout.writeln("token  = " + crypto.randomHex(16))
    return 0
}
