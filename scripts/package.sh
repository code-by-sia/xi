#!/usr/bin/env bash
# Assemble and tar a release bundle for the X toolchain.
#
#   scripts/package.sh <dist-dir> <target-label> <version>
#
# Expects the native binaries to already exist at <dist-dir>/libexec/xc and
# <dist-dir>/libexec/xi. Bundles the runtime + stdlib, writes the bin/ wrappers
# and a README, and produces <dist-dir>.tar.gz. Prints the tarball name.
set -euo pipefail

DIST="$1"; TARGET="$2"; VERSION="$3"

[ -x "$DIST/libexec/xc" ] || { echo "package: missing $DIST/libexec/xc" >&2; exit 1; }
[ -x "$DIST/libexec/xi" ] || { echo "package: missing $DIST/libexec/xi" >&2; exit 1; }
mkdir -p "$DIST/bin"

# the compiler shells out to cc, so it needs the runtime + stdlib alongside it
cp -R runtime "$DIST/runtime"
cp -R std     "$DIST/std"

# wrappers that locate the bundle and set the env vars
cat > "$DIST/bin/xc" <<'SH'
#!/bin/sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XC_RUNTIME="${XC_RUNTIME:-$HERE/runtime}"
export XC_STD="${XC_STD:-$HERE}"
exec "$HERE/libexec/xc" "$@"
SH
cat > "$DIST/bin/xi" <<'SH'
#!/bin/sh
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export XC_RUNTIME="${XC_RUNTIME:-$HERE/runtime}"
export XC_STD="${XC_STD:-$HERE}"
export XC="${XC:-$HERE/bin/xc}"
exec "$HERE/libexec/xi" "$@"
SH
chmod +x "$DIST/bin/xc" "$DIST/bin/xi"

cat > "$DIST/README.txt" <<EOF
Xi toolchain ${VERSION} (${TARGET})

Contents:
  bin/xc   - the Xi compiler (wrapper; sets XC_RUNTIME and XC_STD)
  bin/xi   - the Xi REPL / run tool
  runtime/ - C runtime (xc invokes cc with this)
  std/     - standard library (import "std/...")

Install: put bin/ on your PATH, e.g.
  export PATH="\$PWD/${DIST}/bin:\$PATH"
  xc myprog.x        # -> build/myprog
  xi                 # interactive REPL

Requires a C compiler (cc / clang / gcc) on PATH.
EOF

tar -czf "$DIST.tar.gz" "$DIST"
echo "$DIST.tar.gz"
