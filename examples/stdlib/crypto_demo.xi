// std/crypto — hashing, HMAC, encodings, and secure random (no external libs).
import "std/log.xi"
import "std/crypto.xi"
import "std/bytes.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    // hashes (hex digests of a string)
    logger.print("sha256 = " + crypto.sha256Hex("the Xi language"))
    logger.print("sha1   = " + crypto.sha1Hex("the Xi language"))
    logger.print("md5    = " + crypto.md5Hex("the Xi language"))

    // HMAC-SHA256 (e.g. signing an API token)
    logger.print("hmac   = " + crypto.hmacSha256Hex("secret-key", "message"))

    // encodings
    let raw = bytes.fromString("hello, Xi")
    let b64 = crypto.base64(raw)
    logger.print("base64 = " + b64)
    logger.print("back   = " + bytes.toString(crypto.fromBase64(b64)))
    logger.print("hex    = " + crypto.hex(raw))

    // a fresh random token
    logger.print("token  = " + crypto.randomHex(16))
    return 0
}
