#!/usr/bin/env bash
# Fetch the released X compiler binary that matches this platform and print the
# path to its `xc` executable on stdout. This is the bootstrap seed: there is no
# checked-in C seed — building X requires a previously published release binary
# for this OS/arch (or an explicit override).
#
# Overrides (env):
#   XC_SEED=/path/to/xc          use an existing xc binary, skip the download
#   XC_BOOTSTRAP_VERSION=v0.0.0  pin a release tag (default: latest)
#   XC_BOOTSTRAP_REPO=owner/name (default: code-by-sia/x)
#   GH_TOKEN / GITHUB_TOKEN      used for the GitHub API (avoids rate limits)
#
# Diagnostics go to stderr so stdout is just the binary path.
set -euo pipefail

if [ -n "${XC_SEED:-}" ]; then
    [ -x "$XC_SEED" ] || { echo "fetch-seed: XC_SEED is not executable: $XC_SEED" >&2; exit 1; }
    echo "$XC_SEED"; exit 0
fi

REPO="${XC_BOOTSTRAP_REPO:-code-by-sia/x}"
VER="${XC_BOOTSTRAP_VERSION:-latest}"

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

if [ "$VER" = latest ]; then
    VER=$(curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$REPO/releases/latest" \
          | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)
    [ -n "$VER" ] || { echo "fetch-seed: could not resolve latest release of $REPO" >&2; exit 1; }
fi

cache="${XC_OUT:-build}/.seed/$VER-$target"
seedxc="$cache/x-$VER-$target/libexec/xc"

if [ ! -x "$seedxc" ]; then
    rm -rf "$cache"; mkdir -p "$cache"
    url="https://github.com/$REPO/releases/download/$VER/x-$VER-$target.tar.gz"
    echo "fetch-seed: downloading bootstrap compiler $VER ($target)" >&2
    curl -fSL ${auth[@]+"${auth[@]}"} "$url" -o "$cache/x.tgz" >&2 \
        || { echo "fetch-seed: download failed: $url" >&2; exit 1; }
    tar -xzf "$cache/x.tgz" -C "$cache"
fi

[ -x "$seedxc" ] || { echo "fetch-seed: seed compiler not found: $seedxc" >&2; exit 1; }
echo "$seedxc"
