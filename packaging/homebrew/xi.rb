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
  version "0.0.73"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.73/xi-v0.0.73-macos-arm64.tar.gz"
      sha256 "13cc14ea717ea2eab9d8a7a9830120632740b68493a272cb72f63c68b451d8db"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.73/xi-v0.0.73-macos-x86_64.tar.gz"
      sha256 "2db32611e51525c8cd0e8987ba602bd5fd29d91eed3adcb175a66305f9f27b1a"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.73/xi-v0.0.73-linux-arm64.tar.gz"
      sha256 "c3bd168a69e7c511837152faedcb14bf45daa5da3da13928c5233b1bfaa07ab9"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.73/xi-v0.0.73-linux-x86_64.tar.gz"
      sha256 "40f7514f7401fb8f3b2d933bdce774f4c1560e69ae724bc6496c6c04f60c25e7"
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
