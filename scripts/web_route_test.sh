#!/usr/bin/env bash
# Integration test for web.route path-pattern matching — in particular multiple
# params and a trailing literal segment (/playlists/:playlistId/tracks/:trackId/move),
# which can't be checked by a `test { }` unit (it needs a running HTTP server).
#
# Compiles examples/web_route_move_demo.xi, starts it, curls each route, and
# asserts the JSON response. Exits nonzero on any mismatch.
#
#   scripts/web_route_test.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export XC_RUNTIME="$ROOT/runtime" XC_STD="$ROOT"
PORT=8137
BASE="http://127.0.0.1:$PORT"

echo "==> compiling examples/web_route_move_demo.xi ..."
./compiler/xc examples/web_route_move_demo.xi >/dev/null

"$ROOT/build/web_route_move_demo" >/tmp/web-route-srv.log 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT

# wait for the server to bind (up to ~6s)
for _ in $(seq 1 30); do
    curl -fsS "$BASE/health" >/dev/null 2>&1 && break
    sleep 0.2
done

fail=0
check() {  # $1=method  $2=path  $3=expected-body
    got="$(curl -fsS -X "$1" "$BASE$2" 2>/dev/null || true)"
    if [ "$got" = "$3" ]; then
        echo "  ok    $1 $2 -> $got"
    else
        echo "  FAIL  $1 $2 -> got '$got', expected '$3'"
        fail=1
    fi
}

check GET  "/health"                          '{"ok":true}'
check GET  "/users/9"                          '{"id":9}'
check POST "/playlists/7/tracks/42/move"       '{"playlistId":7,"trackId":42}'
check POST "/playlists/1/tracks/2/move"        '{"playlistId":1,"trackId":2}'

if [ "$fail" -eq 0 ]; then
    echo "web route test: all routes matched ✓"
else
    echo "web route test: FAILED"
    exit 1
fi
