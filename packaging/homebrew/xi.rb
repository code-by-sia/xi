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
  version "0.0.76"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.76/xi-v0.0.76-macos-arm64.tar.gz"
      sha256 "2d5d50c27cb474cf2e50feec1e988221a44ae7168f9e7c6a7a731ba4704598bd"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.76/xi-v0.0.76-macos-x86_64.tar.gz"
      sha256 "063fdea9941d7a0c805b0c76ebc7ffd9a9d43fb30da5585ef83e31343dfc0979"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.76/xi-v0.0.76-linux-arm64.tar.gz"
      sha256 "a3b76a27310adc978119d753de827b02061464f6df416238c6f4903c9e8c3b38"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.76/xi-v0.0.76-linux-x86_64.tar.gz"
      sha256 "ad462e06e10ff4d9ee83bf78947523941f935dca3ebc9e7aec48d4a4ef3148e9"
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
