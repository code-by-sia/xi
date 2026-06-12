# typed: false
# frozen_string_literal: true

# Homebrew formula for the Ξ (Xi) programming language toolchain.
#
# This file is the source of truth for the `code-by-sia/homebrew-x` tap; the
# release workflow regenerates the version/url/sha256 lines via
# `scripts/update-formula.sh` and pushes the result to the tap repo. See
# packaging/homebrew/README.md for the one-time tap setup.
class Xi < Formula
  desc "The Ξ (Xi) programming language toolchain (compiler + REPL)"
  homepage "https://github.com/code-by-sia/x"
  version "0.0.70"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.70/xi-v0.0.70-macos-arm64.tar.gz"
      sha256 "ff113309e4a3a01df4fc20cb5ddc4c3d9e47d84003057b32de3c8cdb360cc7a7"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.70/xi-v0.0.70-macos-x86_64.tar.gz"
      sha256 "e53d3c257fc272349f81205a092c9b46bb5855571f3fb3f31e0f4be2e46cf190"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.70/xi-v0.0.70-linux-arm64.tar.gz"
      sha256 "709c1cd65e6df857a02d7d3365000da8103b723dc5fb3fd7d57f8dc4a7c25207"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.70/xi-v0.0.70-linux-x86_64.tar.gz"
      sha256 "384bd9ececad7b9695559b969ecf1fb45914d4d555399fa07a5b8168d001fb34"
    end
  end

  def install
    # The tarball expands to a single top-level dir (Homebrew has already cd'd
    # into it). Stash the bundle under libexec and write absolute-path wrappers
    # so xc/xi find the runtime and stdlib regardless of how bin is symlinked.
    libexec.install Dir["*"]

    (bin/"xc").write <<~SH
      #!/bin/sh
      export XC_RUNTIME="${XC_RUNTIME:-#{libexec}/runtime}"
      export XC_STD="${XC_STD:-#{libexec}}"
      exec "#{libexec}/libexec/xc" "$@"
    SH

    (bin/"xi").write <<~SH
      #!/bin/sh
      export XC_RUNTIME="${XC_RUNTIME:-#{libexec}/runtime}"
      export XC_STD="${XC_STD:-#{libexec}}"
      export XC="${XC:-#{bin}/xc}"
      exec "#{libexec}/libexec/xi" "$@"
    SH

    chmod 0755, bin/"xc"
    chmod 0755, bin/"xi"
  end

  def caveats
    <<~EOS
      xc compiles Xi to C and invokes a C compiler to produce native binaries,
      so a working `cc` (clang/gcc) must be on your PATH.
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
