#!/usr/bin/env bash
# Self-hosting verification.
#
#   gen0 = xc built from compiler/xc.stage0.c with cc   (C bootstrap seed)
#   gen1 = compiler/xc.x compiled by gen0                (X compiling X)
#   gen2 = compiler/xc.x compiled by gen1
#
# A stable self-hosting compiler emits byte-identical C for xc.x at each stage.
#
#   ./compiler/selfhost.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export XC_RUNTIME="$ROOT/runtime"
HELP="$ROOT/compiler/xc_helpers.c"
W=/tmp/xc_selfhost; rm -rf "$W"; mkdir -p "$W"

# Copy ALL compiler sources so relative `import`s resolve in the work dir.
cp compiler/*.x "$W"/

echo "==> [gen0] cc builds xc from compiler/xc.stage0.c (no pre-existing X binary)"
cc -std=c99 -O2 -w -I runtime compiler/xc.stage0.c runtime/runtime.c -o "$W/xc_gen0" -lm

echo "==> gen0 compiles xc.x -> gen1"
( cd "$W" && XC_HELPERS="$HELP" XC_RUNTIME="$ROOT/runtime" XC_OUT=. ./xc_gen0 xc.x >/dev/null )
cp "$W/xc.gen.c" "$W/c1.c"; cp "$W/xc" "$W/xc_gen1"

echo "==> gen1 compiles xc.x -> gen2"
( cd "$W" && XC_HELPERS="$HELP" XC_RUNTIME="$ROOT/runtime" XC_OUT=. ./xc_gen1 xc.x >/dev/null )
cp "$W/xc.gen.c" "$W/c2.c"; cp "$W/xc" "$W/xc_gen2"

echo
echo "==> Fixpoint: gen0's C output for xc.x == gen1's C output?"
if diff -q "$W/c1.c" "$W/c2.c" >/dev/null; then
    echo "    ✓ byte-identical ($(wc -l < "$W/c1.c") lines) — stable self-hosting fixpoint"
else
    echo "    ✗ differ"; diff "$W/c1.c" "$W/c2.c" | head; exit 1
fi

echo
echo "==> gen2 compiles the examples:"
fail=0
for ex in hello refined_types greeting features overload errors; do
    [ -f "examples/$ex.x" ] || continue
    cp "examples/$ex.x" "$W/$ex.x"
    ( cd "$W" && XC_OUT=. XC_RUNTIME="$ROOT/runtime" ./xc_gen2 "$ex.x" >/dev/null 2>&1 )
    if [ -x "$W/$ex" ]; then echo "    ✓ $ex -> $("$W/$ex" 2>&1 | head -1)"; else echo "    ✗ $ex"; fail=1; fi
done
[ "$fail" = 0 ] && echo && echo "SELF-HOSTING VERIFIED — bootstraps from C source."
