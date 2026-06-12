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
  version "0.0.71"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.71/xi-v0.0.71-macos-arm64.tar.gz"
      sha256 "9dc9417eabdcd280e0a50f4f8f113edbaee734ccec71d6c844a96cd6dae9ca3b"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.71/xi-v0.0.71-macos-x86_64.tar.gz"
      sha256 "1ccd407e65f98fe1821ecb9f1ce88dcb8dcf2aece41680ed05609ad757c9700d"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.71/xi-v0.0.71-linux-arm64.tar.gz"
      sha256 "927b8f762b1eb2e4c95103b5f6c92953b4d3e0e46c3fa5553c57ca1c0491368d"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.71/xi-v0.0.71-linux-x86_64.tar.gz"
      sha256 "ce51cd5cbf1a143bbbc38d225f98160039986de90341118eb107a33315fff946"
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
