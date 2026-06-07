#!/usr/bin/env bash
# Self-hosting verification (no checked-in C seed).
#
#   gen0 = the released X compiler for this platform (bootstrap seed)
#   gen1 = compiler/xc.xi compiled by gen0     (current source, seed codegen)
#   gen2 = compiler/xc.xi compiled by gen1     (current source, current codegen)
#   gen3 = compiler/xc.xi compiled by gen2
#
# A stable self-hosting compiler emits byte-identical C once the source is
# compiling itself. We therefore require gen2's and gen3's C output to match
# (both produced by current-source compilers) — this holds even if the seed
# release predates the working-tree source.
#
#   ./compiler/selfhost.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export XC_RUNTIME="$ROOT/runtime"
HELP="$ROOT/compiler/xc_helpers.c"
W=/tmp/xc_selfhost; rm -rf "$W"; mkdir -p "$W"

# Copy ALL compiler sources so relative `import`s resolve in the work dir.
cp compiler/*.xi "$W"/

echo "==> [gen0] seed = released X compiler (no checked-in C seed)"
SEED="$("$ROOT/compiler/fetch-seed.sh")"
cp "$SEED" "$W/xc_gen0"; chmod +x "$W/xc_gen0"

compile_with() {  # $1 = compiler binary, $2 = output C copy
    ( cd "$W" && XC_KEEP_C=1 XC_HELPERS="$HELP" XC_RUNTIME="$ROOT/runtime" XC_OUT=. "$1" xc.xi >/dev/null )
    cp "$W/xc.gen.c" "$2"
}

echo "==> gen0 compiles xc.xi -> gen1"
compile_with "$W/xc_gen0" "$W/c1.c"; cp "$W/xc" "$W/xc_gen1"

echo "==> gen1 compiles xc.xi -> gen2"
compile_with "$W/xc_gen1" "$W/c2.c"; cp "$W/xc" "$W/xc_gen2"

echo "==> gen2 compiles xc.xi -> gen3"
compile_with "$W/xc_gen2" "$W/c3.c"; cp "$W/xc" "$W/xc_gen3"

echo
echo "==> Fixpoint: gen2's C output for xc.xi == gen3's C output?"
if diff -q "$W/c2.c" "$W/c3.c" >/dev/null; then
    echo "    ✓ byte-identical ($(wc -l < "$W/c2.c") lines) — stable self-hosting fixpoint"
else
    echo "    ✗ differ"; diff "$W/c2.c" "$W/c3.c" | head; exit 1
fi

echo
echo "==> gen3 compiles the examples:"
fail=0
for ex in hello refined_types greeting features overload errors; do
    [ -f "examples/$ex.xi" ] || continue
    cp "examples/$ex.xi" "$W/$ex.xi"
    ( cd "$W" && XC_OUT=. XC_RUNTIME="$ROOT/runtime" XC_STD="$ROOT" ./xc_gen3 "$ex.xi" >/dev/null 2>&1 )
    if [ -x "$W/$ex" ]; then echo "    ✓ $ex -> $("$W/$ex" 2>&1 | head -1)"; else echo "    ✗ $ex"; fail=1; fi
done
[ "$fail" = 0 ] && echo && echo "SELF-HOSTING VERIFIED — source compiles itself to a fixpoint."
