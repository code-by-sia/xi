# typed: false
# frozen_string_literal: true

# Homebrew formula for the Ξ (Xi) programming language toolchain.
#
# This file is the source of truth for the `code-by-sia/homebrew-xi` tap; the
# release workflow regenerates the version/url/sha256 lines via
# `scripts/update-formula.sh` and pushes the result to the tap repo. See
# packaging/homebrew/README.md for the one-time tap setup.
class Xi < Formula
  desc "The Ξ (Xi) programming language toolchain (compiler + REPL)"
  homepage "https://github.com/code-by-sia/xi"
  version "0.1.7"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.7/xi-v0.1.7-macos-arm64.tar.gz"
      sha256 "ac05575c93ed4636ccdef3aeaf1b1847dc78f3c7ae6dc1c17fb7c2ddb94c49cb"
    end
    on_intel do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.7/xi-v0.1.7-macos-x86_64.tar.gz"
      sha256 "cb0149186778538c92529e7002f0c989f84617340f08ceb62e2c1a7acd4f4714"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.7/xi-v0.1.7-linux-arm64.tar.gz"
      sha256 "43211ddf3a99c8060045f8fc561006bca5a8dde74075c05e2066aa7a9313d269"
    end
    on_intel do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.7/xi-v0.1.7-linux-x86_64.tar.gz"
      sha256 "cf88784e0e06cf0c04b02a8672d0a2bf323a33a79ee0d44a37bf39e3dd5538b6"
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
