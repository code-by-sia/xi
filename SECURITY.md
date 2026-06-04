# Security Policy

## Supported versions

Xi is pre-1.0 and experimental. Only the **latest release** receives fixes;
older releases are not maintained.

| Version        | Supported       |
|----------------|-----------------|
| latest release | ✓ (best effort) |
| older          | ✗               |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue or PR.

- Preferred: GitHub's **private vulnerability reporting**
  (the repository's *Security → Report a vulnerability* tab), or
- Email: **me@siamand.cc**

Include a description, affected version/commit, and steps to reproduce if
possible. You'll get an acknowledgement on a best-effort basis; there is no
guaranteed response time or fix timeline.

## Scope and disclaimer

Xi compiles Xi source to C and invokes a C compiler. Compiling or running
untrusted Xi source is equivalent to running untrusted code — do so only in a
sandbox. The software is provided **as is, without warranty**, per the
[LICENSE](LICENSE).
