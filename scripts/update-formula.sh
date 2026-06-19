#!/usr/bin/env bash
# Regenerate the Homebrew formula (packaging/homebrew/xi.rb) for a release.
#
#   scripts/update-formula.sh <version> [asset-dir]
#
# <version>    e.g. 0.0.67 or v0.0.67 (the leading "v" is optional).
# [asset-dir]  directory holding the release tarballs. If omitted, the four
#              platform tarballs are downloaded from the GitHub release for the
#              matching tag. sha256 sums are computed from whichever is used.
#
# Tarball names follow the release convention: xi-v<version>-<target>.tar.gz
# for target in {macos-arm64, macos-x86_64, linux-x86_64, linux-arm64}.
set -euo pipefail

REPO="code-by-sia/xi"
TARGETS=(macos-arm64 macos-x86_64 linux-x86_64 linux-arm64)

raw="${1:?usage: update-formula.sh <version> [asset-dir]}"
VER="${raw#v}"            # strip leading v -> 0.0.67
TAG="v${VER}"            # v0.0.67
ASSET_DIR="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/packaging/homebrew/xi.rb"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sha_for() {
  local target="$1" file
  file="xi-${TAG}-${target}.tar.gz"
  if [ -n "$ASSET_DIR" ]; then
    [ -f "$ASSET_DIR/$file" ] || { echo "missing $ASSET_DIR/$file" >&2; exit 1; }
    cp "$ASSET_DIR/$file" "$WORK/$file"
  else
    curl -fsSL -o "$WORK/$file" \
      "https://github.com/$REPO/releases/download/$TAG/$file" \
      || { echo "failed to download $file" >&2; exit 1; }
  fi
  shasum -a 256 "$WORK/$file" 2>/dev/null | cut -d' ' -f1 \
    || sha256sum "$WORK/$file" | cut -d' ' -f1
}

# bash 3.2 (stock macOS) has no associative arrays, so use plain vars.
SHA_macos_arm64="$(sha_for macos-arm64)";   echo "  macos-arm64  $SHA_macos_arm64" >&2
SHA_macos_x86_64="$(sha_for macos-x86_64)"; echo "  macos-x86_64 $SHA_macos_x86_64" >&2
SHA_linux_x86_64="$(sha_for linux-x86_64)"; echo "  linux-x86_64 $SHA_linux_x86_64" >&2
SHA_linux_arm64="$(sha_for linux-arm64)";   echo "  linux-arm64  $SHA_linux_arm64" >&2

url() { echo "https://github.com/$REPO/releases/download/$TAG/xi-${TAG}-$1.tar.gz"; }

cat > "$OUT" <<EOF
# typed: false
# frozen_string_literal: true

# Homebrew formula for the Ξ (Xi) programming language toolchain.
#
# This file is the source of truth for the \`code-by-sia/homebrew-xi\` tap; the
# release workflow regenerates the version/url/sha256 lines via
# \`scripts/update-formula.sh\` and pushes the result to the tap repo. See
# packaging/homebrew/README.md for the one-time tap setup.
class Xi < Formula
  desc "The Ξ (Xi) programming language toolchain (compiler + REPL)"
  homepage "https://github.com/$REPO"
  version "$VER"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "$(url macos-arm64)"
      sha256 "${SHA_macos_arm64}"
    end
    on_intel do
      url "$(url macos-x86_64)"
      sha256 "${SHA_macos_x86_64}"
    end
  end

  on_linux do
    on_arm do
      url "$(url linux-arm64)"
      sha256 "${SHA_linux_arm64}"
    end
    on_intel do
      url "$(url linux-x86_64)"
      sha256 "${SHA_linux_x86_64}"
    end
  end

  def install
    # The tarball expands to a single top-level dir (Homebrew has already cd'd
    # into it). Stash the bundle under libexec and write absolute-path wrappers
    # so xc/xi find the runtime and stdlib regardless of how bin is symlinked.
    libexec.install Dir["*"]

    (bin/"xc").write <<~SH
      #!/bin/sh
      export XC_RUNTIME="\${XC_RUNTIME:-#{libexec}/runtime}"
      export XC_STD="\${XC_STD:-#{libexec}}"
      exec "#{libexec}/libexec/xc" "\$@"
    SH

    (bin/"xi").write <<~SH
      #!/bin/sh
      export XC_RUNTIME="\${XC_RUNTIME:-#{libexec}/runtime}"
      export XC_STD="\${XC_STD:-#{libexec}}"
      export XC="\${XC:-#{bin}/xc}"
      exec "#{libexec}/libexec/xi" "\$@"
    SH

    chmod 0755, bin/"xc"
    chmod 0755, bin/"xi"
  end

  def caveats
    <<~EOS
      xc compiles Xi to C and invokes a C compiler to produce native binaries,
      so a working \`cc\` (clang/gcc) must be on your PATH.
    EOS
  end

  test do
    (testpath/"hello.xi").write <<~XI
      import "std/log.xi"
      async entry (logger: Logger) main(args: String[]) {
          logger.info("brew ok")
      }
      module App {}
    XI
    assert_match "brew ok", shell_output("#{bin}/xi hello.xi")
  end
end
EOF

echo "wrote $OUT (version $VER)" >&2
