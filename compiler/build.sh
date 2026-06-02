#!/usr/bin/env bash
# Compile an X program to a native executable using the X compiler.
#
#   ./compiler/build.sh examples/hello.x   # -> ./examples/hello
#
# If compiler/xc does not exist yet, bootstrap it from source first.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export XC_RUNTIME="$ROOT/runtime"

if [ ! -x compiler/xc ]; then
    echo "==> compiler/xc not found; bootstrapping from source ..."
    ./compiler/bootstrap.sh
fi

if [ "$#" -lt 1 ]; then
    echo "usage: ./compiler/build.sh <source.x>"
    exit 1
fi

src="$1"
./compiler/xc "$src"
echo "built: ${src%.x}"
