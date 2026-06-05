# Proposal: Web stack — crypto → HTTPS → HTTP/2-3 → `std/web`

> **Status: phased.** Phase 1 (**`std/crypto`**) and Phase 4 (**`std/web`**, over
> plain HTTP) are **implemented** — see [crypto](../stdlib.md) and [Web](../web.md).
> The transport phases (HTTPS, HTTP/2 and /3) remain and are **gated on one
> decision: the external-dependency policy** (below) — resolved as **Option A,
> optional system libs**; HTTPS is the next build.

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

## Phase 2 — HTTPS

- **Client:** extend `std/http` so `https://` URLs work — wrap the existing `net`
  socket in a TLS session (handshake, read/write) via the chosen TLS lib.
- **Server:** a TLS listener (cert + key) producing encrypted `net.Conn`s.
- API stays the same shape as today's `std/http`; only the transport changes.

## Phase 3 — HTTP/2, then HTTP/3

- **HTTP/2** over TLS (ALPN `h2`): framing + HPACK via `nghttp2`, exposed behind
  the same request/response types.
- **HTTP/3** over QUIC (UDP): a QUIC library (`ngtcp2`+`nghttp3` or `quiche`).
  Highest dependency weight; last in line.
- Negotiation is transparent (ALPN); callers keep one API.

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
