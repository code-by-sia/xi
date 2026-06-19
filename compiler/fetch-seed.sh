#!/usr/bin/env bash
# Fetch a released X compiler binary that matches this platform and print the
# path to its `xc` executable on stdout. This is the bootstrap seed: building X
# requires a previously published release binary for this OS/arch.
#
# Resolution order (first one with a matching-platform asset wins):
#   1. XC_SEED=/path/to/xc        — use an existing binary, no download
#   2. XC_BOOTSTRAP_VERSION=vX     — try this tag first (default: none)
#   3. published releases, newest first — so an in-progress release whose asset
#      isn't uploaded yet is skipped and the PREVIOUS release is used instead.
#
#   XC_BOOTSTRAP_REPO=owner/name  (default: code-by-sia/xi)
#   GH_TOKEN / GITHUB_TOKEN       used for the GitHub API (avoids rate limits)
#
# Diagnostics go to stderr so stdout is just the binary path.
set -euo pipefail

if [ -n "${XC_SEED:-}" ]; then
    [ -x "$XC_SEED" ] || { echo "fetch-seed: XC_SEED is not executable: $XC_SEED" >&2; exit 1; }
    echo "$XC_SEED"; exit 0
fi

REPO="${XC_BOOTSTRAP_REPO:-code-by-sia/xi}"

os=$(uname -s); arch=$(uname -m)
case "$os" in
    Linux)  o=linux ;;
    Darwin) o=macos ;;
    *) echo "fetch-seed: unsupported OS: $os" >&2; exit 1 ;;
esac
case "$arch" in
    x86_64|amd64)  a=x86_64 ;;
    arm64|aarch64) a=arm64 ;;
    *) echo "fetch-seed: unsupported arch: $arch" >&2; exit 1 ;;
esac
target="$o-$a"

auth=()
tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$tok" ] && auth=(-H "Authorization: Bearer $tok")

# Candidate versions: a pin (if any) first, then published tags newest-first.
candidates=""
pin="${XC_BOOTSTRAP_VERSION:-}"
if [ -n "$pin" ] && [ "$pin" != latest ]; then candidates="$pin"; fi
tags=$(curl -fsSL ${auth[@]+"${auth[@]}"} \
        "https://api.github.com/repos/$REPO/releases?per_page=50" 2>/dev/null \
       | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true)
candidates="$candidates $tags"

cache="${XC_OUT:-build}/.seed"
mkdir -p "$cache"

# Release artifacts are "<prefix>-<ver>-<target>.tar.gz" with the seed compiler
# at "<prefix>-<ver>-<target>/libexec/xc". The toolchain was renamed X -> Xi, so
# newer releases use the "xi" prefix; try that first and fall back to the legacy
# "x" prefix so the bootstrap chain across the rename keeps working.
for ver in $candidates; do
    [ -n "$ver" ] || continue
    for prefix in xi x; do
        bundle="$prefix-$ver-$target"
        seedxc="$cache/$ver-$target/$bundle/libexec/xc"
        if [ -x "$seedxc" ]; then echo "$seedxc"; exit 0; fi      # cached

        dst="$cache/$ver-$target"
        url="https://github.com/$REPO/releases/download/$ver/$bundle.tar.gz"
        rm -rf "$dst"; mkdir -p "$dst"
        if curl -fsSL ${auth[@]+"${auth[@]}"} "$url" -o "$dst/x.tgz" 2>/dev/null \
           && tar -xzf "$dst/x.tgz" -C "$dst" 2>/dev/null \
           && [ -x "$seedxc" ]; then
            echo "fetch-seed: using bootstrap seed $ver ($bundle)" >&2
            echo "$seedxc"; exit 0
        fi
        rm -rf "$dst"                                             # no $prefix asset; try next
    done
done

echo "fetch-seed: no release with a '$target' asset found in $REPO" >&2
exit 1
