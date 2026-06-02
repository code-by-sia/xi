# How it works (self-hosting)

## The compiler is written in X

`compiler/xc.x` is the X compiler, written in X. It is split across four files
(imported by the `xc.x` manifest):

| File | Role |
|------|------|
| `lexer.x`   | source text → tokens |
| `parser.x`  | tokens → `Program` (spec structs) |
| `codegen.x` | `Program` → C99 |
| `driver.x`  | `import` resolution + entry point |

The compiler emits C and then invokes `cc` to produce a native binary. The only
non-X code is:

- `runtime/runtime.{h,c}` — the runtime: primitive types, strings, arrays,
  optionals, regex for refined-type `matches`, file/stdin I/O, and the
  `cc`-invocation helper. This is X's equivalent of libc/libcore.
- `compiler/xc_helpers.c` — C primitives the compiler declares via `extern "C"`
  (growable typed arrays, file I/O, `cc` invocation). It is appended into the
  generated C, sharing the translation unit.

## Bootstrapping from source

Self-hosting has a chicken-and-egg problem: you need a compiler to build the
compiler. X solves it the standard way — by shipping the compiler's own emitted
C as a seed:

```
compiler/xc.stage0.c   (the X compiler's C output, checked in)
        │  cc xc.stage0.c runtime.c -o xc
        ▼
       xc   (works immediately, no X compiler needed)
        │  xc compiler/xc.x          (X compiling X)
        ▼
       xc   (rebuilt from source)
```

`./compiler/bootstrap.sh` runs exactly this, then refreshes `stage0.c` from the
freshly self-built compiler.

## The fixpoint test

A correct self-hosting compiler is a **fixpoint**: compiling its own source with
generation *N* yields the same C as generation *N+1*.

```
gen0 = xc built from stage0.c with cc
gen1 = xc.x compiled by gen0
gen2 = xc.x compiled by gen1
assert  C(gen0 on xc.x) == C(gen1 on xc.x)     # byte-identical
```

`./compiler/selfhost.sh` performs this three-stage build and diffs the outputs.

## Compilation pipeline

```
source.x (+ imported files)
  ↓ load     resolve imports, apply namespace prefixing      (driver.x)
  ↓ lex      tokeniser                                        (lexer.x)
  ↓ parse    recursive descent → Program                     (parser.x)
  ↓ codegen  DI wiring, vtables, refined types, overloads,
             results, match, …  → C99                         (codegen.x)
  ↓ cc       C → native binary
```

## What runs at runtime

DI resolution, overload dispatch tables, and refined-type layout are decided at
compile time. At runtime you pay for: one branch per `when`/overload guard, one
vtable indirection per (non-devirtualized) interface call, and the async
state-machine when used. There is no VM, no GC, and no reflection.

## Project layout

```
compiler/
  xc.x          manifest (imports the parts)
  lexer.x parser.x codegen.x driver.x   the compiler, in X
  repl.x        the REPL / run tool (compiled to ./x)
  xc_helpers.c  C primitives (extern "C")
  xc.stage0.c   generated C seed (cc-only bootstrap)
  bootstrap.sh build.sh selfhost.sh
runtime/
  runtime.h runtime.c   the C runtime
examples/
  *.x            single-file examples
  proj/          multi-file example (import + namespace)
docs/            this documentation (MkDocs)
```
