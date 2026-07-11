# WebAssembly

Xi compiles to portable C99 and then invokes a C compiler - so targeting the
web is a matter of swapping that compiler for [Emscripten](https://emscripten.org).
`xc --target wasm <source.xi>` builds the **same** program and runtime to
WebAssembly instead of a native binary; codegen is unchanged.

```console
$ xc --target wasm examples/stdlib/wasm_demo.xi
xc: built WebAssembly build/wasm_demo.{html,js,wasm}
xc: serve it, e.g.  python3 -m http.server -d build  then open wasm_demo.html
```

This emits three files in `$XC_OUT` (default `build/`):

| File | Purpose |
|------|---------|
| `<name>.wasm` | the compiled module |
| `<name>.js` | the loader/glue that instantiates the module |
| `<name>.html` | a ready-to-open page that runs `entry main` and shows output |

`stdout`/`stderr` are wired to the page console (and the browser devtools
console). You can also run the build headless under Node - `node build/<name>.js`
- which is handy in CI.

## Requirements

Emscripten must be on your `PATH`:

```console
$ brew install emscripten     # macOS
# or follow https://emscripten.org/docs/getting_started/downloads.html
$ emcc --version
```

If `emcc` is missing, `xc --target wasm` prints an install hint and stops; the
native build needs only `cc` and is unaffected.

## Serving the page

Browsers won't instantiate a `.wasm` over `file://`, so serve the directory:

```console
$ python3 -m http.server -d build
# open http://localhost:8000/wasm_demo.html
```

## What runs in the browser

The build is single-threaded and runs in the browser sandbox, so portability
follows the platform - not Xi:

| Works | Notes |
|-------|-------|
| Pure computation, strings, arrays, math | identical to native |
| `system.stdout` / `system.stderr` | routed to the page/devtools console |
| File I/O (`std/fs`) | operates on Emscripten's in-memory virtual filesystem, not the user's disk |
| Randomness | backed by the browser crypto API |

| Limited / unavailable | Why |
|-----------------------|-----|
| TCP servers & raw sockets (`std/net`, `std/web` server) | the browser has no listening sockets; client networking must go through `fetch`/WebSockets |
| Spawning processes / `run_command` | no process model in the sandbox |
| TLS / HTTP/2 native links (`XC_TLS`, `XC_HTTP2`) | host libraries (OpenSSL, nghttp2) aren't linked into the WASM build |
| Native FFI (`extern "C"` linking `-l<lib>`) | host shared libraries don't exist in the sandbox; a library must itself be compiled to WASM |

A good rule of thumb: anything that is pure logic or talks only to `stdout`
ports cleanly today. Anything that reaches the operating system (sockets,
processes, real files) needs a browser-shaped replacement.

## Calling Xi from JavaScript

The current target runs a whole program (`entry main`) end to end. Exporting
individual Xi functions to call from JavaScript - with value marshaling across
the JS↔WASM boundary - is a planned next step and not yet wired up.

## See also

- [CLI › `xc --target wasm`](cli.md#webassembly--xc---target-wasm)
- [FFI](ffi.md) - the same C-interop seam the WASM target builds on
