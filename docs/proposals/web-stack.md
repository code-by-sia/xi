# Proposal: Web stack — crypto → HTTPS → HTTP/2-3 → `std/web`

> **Status: nearly done.** Shipped: Phase 1 (**`std/crypto`**), Phase 4
> (**`std/web`**), **HTTPS** server + client (`XC_TLS=1`), and **HTTP/2**
> (`web.serveHttp2`, `XC_HTTP2=1`) — see [crypto](../stdlib.md) and [Web](../web.md).
> External deps follow **Option A, optional system libs**. **Only HTTP/3 (QUIC)
> remains** — deferred to a dedicated effort (see Phase 3).

## Goal

Let a developer stand up a **REST API served over HTTPS** with a few lines of Xi,
reusing what's already shipped: `std/json` for bodies, `std/crypto` for tokens/
signing, dependency injection for handlers, and the `std/http`/`std/net` stack for
transport.

## Phase 1 — Cryptography ✅ (shipped)

`std/crypto`: SHA-256/SHA-1/MD5, HMAC-SHA256, hex/base64, and CSPRNG bytes — all
self-contained C, test-vector verified. Enough for token signing, content hashes,
and API-key HMACs. (AES/ChaCha20 and X25519/ECDSA can follow if needed; those are
larger but still implementable in pure C.)

## The gating decision: TLS / HTTP dependencies

Everything past crypto needs **TLS**, and HTTP/2-3 need framing/QUIC stacks.
Writing a correct, *secure* TLS 1.3 or a QUIC stack from scratch is not advisable
(it's thousands of lines and a security liability). The realistic options:

- **A. Optional system libraries.** Link against the platform's TLS/HTTP stack
  **when present** — `libssl`/`libcrypto` (OpenSSL/LibreSSL) for TLS 1.2/1.3,
  `nghttp2` for HTTP/2, and a QUIC lib (`ngtcp2`+`nghttp3`, or `quiche`) for
  HTTP/3. The compiler would add `-lssl -lcrypto …` to the `cc` invocation only
  when a module that needs them is imported. **Cost:** breaks the current
  “dependency-light, just libc + `-lm`” promise; the runtime gains optional deps.
- **B. From scratch.** Implement TLS/HTTP2/HTTP3 in pure C. **Not recommended** —
  enormous and a security risk; effectively out of scope.

**Recommendation: A**, scoped tightly — TLS first (HTTPS covers the vast majority
of "REST API" needs), then HTTP/2, then HTTP/3 (which carries the heaviest
dependency, QUIC). Each is opt-in via its `import`.

## Phase 2 — HTTPS ✅ (shipped)

- **Server:** ✅ `web.serveTLS(port, cert, key)` wraps each accepted socket in an
  OpenSSL TLS session and runs the existing handler stack. Opt-in via `XC_TLS=1`
  at compile time (links `libssl`/`libcrypto`); default builds stay
  dependency-light and `serveTLS` degrades to a notice.
- **Client:** ✅ `std/http` now handles `https://` URLs — the runtime does the
  TLS round-trip (connect, SNI handshake, request, read) via `xstd_https_fetch`,
  also gated on `XC_TLS=1`.

## Phase 3 — HTTP/2 ✅, then HTTP/3 (remaining)

- **HTTP/2** ✅ `web.serveHttp2(port, cert, key)` — framing + HPACK via `nghttp2`
  over TLS, ALPN `h2`, falling back to HTTP/1.1. Same handler stack and
  request/response types. Opt-in via `XC_HTTP2=1` (links OpenSSL + nghttp2).
- **HTTP/3** over QUIC (UDP) — **remaining.** Needs a QUIC library
  (`ngtcp2`+`nghttp3` or `quiche`); highest dependency weight and security
  surface, and not yet broadly available (no system QUIC lib / HTTP/3 client on
  common dev setups), so it's deferred to a dedicated effort rather than shipped
  untested. This is the one open item in the web stack.

## Phase 4 — `std/web` (REST framework) — **shipped**

A small framework so a server is declarative and DI-wired. Implement
`WebRequestHandler` and route by overloading `handle` with `where` guards;
payloads auto-(de)serialize via a `WebTransport`:

```x
import "std/web.xi"

event User { name: String, active: Bool }

class Users implements WebRequestHandler {
    deps { db: Repo }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/user" {
        res.send(db.find(req.query("name")))    // res.send serializes via WebTransport
    }
}

async entry main(args: String[]) -> Integer {
    web.serve(8080)
    return 0
}
module App {}                                   // controllers auto-register — no bind
```

- **`action`** — an impure function kind (may mutate; not pure). The handler
  contract `WebRequestHandler.handle` is an `action`.
- **Auto-registered controllers** — every class implementing `WebRequestHandler`
  is discovered and DI-wired automatically (no `bind`); the server tries each in
  order and the first matching overload wins.
- **`where`-overloaded methods** — routing is method overloading on `handle`:
  the first overload whose guard holds runs.
- **`HttpRequest`** — `path`, `method`, `body`, `query`, `header`, and
  `parse(T)` (typed body). **`HttpResponse`** is mutable: `send(dto)`,
  `sendStatus(code, msg)`, `sendText(code, body)`.
- **`WebTransport`** — pluggable (de)serialization; JSON by default, replaceable
  by binding another implementor.
- **`web.serve(port)`** (HTTP) ships today; **`web.serveTLS(port, cert, key)`**
  (HTTPS) with HTTP/2-3 negotiated transparently is still future work.
- Middleware (auth via `std/crypto` HMAC/JWT, logging) as ordinary DI-wired
  components.

## Open question for you

How should we handle the TLS/HTTP dependency (the gate above)?

1. **Option A — optional system libs** (OpenSSL for TLS now; nghttp2 / QUIC lib
   later), linked only when the relevant module is imported. *(recommended)*
2. **Vendored TLS** — bundle a small TLS library's source in `runtime/` so there's
   no system dependency, at the cost of carrying that code.
3. **Hold** HTTPS+ until there's a clearer dependency policy.

Crypto (phase 1) is done regardless; the rest proceeds once this is settled.
