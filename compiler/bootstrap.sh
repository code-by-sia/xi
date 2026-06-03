#!/usr/bin/env bash
# Bootstrap the X compiler FROM SOURCE using only a C compiler.
#
# `compiler/xc.stage0.c` is the X compiler's own C output for `compiler/xc.x`
# (with the C helpers appended).  Compiling it with cc + the runtime yields a
# working `xc` — no pre-existing X binary required.
#
# Then we use that compiler to rebuild itself from `compiler/xc.x`, proving the
# toolchain is self-contained.
#
#   ./compiler/bootstrap.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export XC_RUNTIME="$ROOT/runtime"
export XC_OUT="$ROOT/build"          # all build artifacts land here
HELP="$ROOT/compiler/xc_helpers.c"
mkdir -p "$XC_OUT"

echo "==> [stage0] Building xc from compiler/xc.stage0.c with cc ..."
cc -std=c99 -O2 -w -Wno-implicit-int -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -I runtime compiler/xc.stage0.c runtime/runtime.c -o compiler/xc -lm
echo "    built compiler/xc"

echo "==> [stage1] Rebuilding xc from compiler/xc.x using the stage0 compiler ..."
XC_HELPERS="$HELP" ./compiler/xc compiler/xc.x >/dev/null
cp "$XC_OUT/xc" compiler/xc
echo "    compiler/xc now built by itself"

echo "==> Refreshing compiler/xc.stage0.c from the self-built compiler ..."
XC_HELPERS="$HELP" ./compiler/xc compiler/xc.x >/dev/null
cp "$XC_OUT/xc.gen.c" compiler/xc.stage0.c
echo "    stage0 refreshed"

echo "==> Building the REPL / run tool 'x' from compiler/repl.x ..."
./compiler/xc compiler/repl.x >/dev/null
mkdir -p bin
cp "$XC_OUT/repl" bin/x
echo "    built ./bin/x"

echo "Bootstrap complete. The compiler is built entirely from X + C."
echo "  ./compiler/xc <file.x>   compile to a native binary"
echo "  ./bin/x                  start the REPL"
echo "  ./bin/x <file.x>         compile and run a file"
