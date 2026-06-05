// std/crypto — hashing, HMAC, encodings, and secure random.  import "std/crypto.xi"
//
// Self-contained (no external libraries). Digests are `Bytes`; use `hex` or
// `base64` to render them. For text input, wrap with `bytes.fromString(s)`.
namespace crypto

import "std/bytes.xi"

extern "C" {
    mapper xstd_sha256(b: Bytes) -> Bytes
    mapper xstd_sha1(b: Bytes) -> Bytes
    mapper xstd_md5(b: Bytes) -> Bytes
    mapper xstd_hmac_sha256(key: Bytes, msg: Bytes) -> Bytes
    mapper xstd_hex(b: Bytes) -> String
    mapper xstd_unhex(s: String) -> Bytes
    mapper xstd_base64(b: Bytes) -> String
    mapper xstd_unbase64(s: String) -> Bytes
    producer xstd_random_bytes(n: Integer) -> Bytes
}

// ── Hashes ──────────────────────────────────────────────────────────
mapper sha256(b: Bytes) -> Bytes { return xstd_sha256(b) }
mapper sha1(b: Bytes) -> Bytes   { return xstd_sha1(b) }
mapper md5(b: Bytes) -> Bytes    { return xstd_md5(b) }

// Convenience: hash a String, return a hex digest.
mapper sha256Hex(s: String) -> String { return xstd_hex(xstd_sha256(bytes.fromString(s))) }
mapper sha1Hex(s: String) -> String   { return xstd_hex(xstd_sha1(bytes.fromString(s))) }
mapper md5Hex(s: String) -> String    { return xstd_hex(xstd_md5(bytes.fromString(s))) }

// ── HMAC ────────────────────────────────────────────────────────────
mapper hmacSha256(key: Bytes, msg: Bytes) -> Bytes { return xstd_hmac_sha256(key, msg) }
mapper hmacSha256Hex(key: String, msg: String) -> String {
    return xstd_hex(xstd_hmac_sha256(bytes.fromString(key), bytes.fromString(msg)))
}

// ── Encodings ───────────────────────────────────────────────────────
mapper hex(b: Bytes) -> String        { return xstd_hex(b) }
mapper fromHex(s: String) -> Bytes     { return xstd_unhex(s) }
mapper base64(b: Bytes) -> String      { return xstd_base64(b) }
mapper fromBase64(s: String) -> Bytes  { return xstd_unbase64(s) }

// ── Secure random ───────────────────────────────────────────────────
producer randomBytes(n: Integer) -> Bytes { return xstd_random_bytes(n) }
producer randomHex(n: Integer) -> String  { return xstd_hex(xstd_random_bytes(n)) }
