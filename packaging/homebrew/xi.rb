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
  version "0.0.69"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.69/xi-v0.0.69-macos-arm64.tar.gz"
      sha256 "78fe837421804538a2af1ae63d08749b4c2eb94c70342f6c7553296e097e4ce3"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.69/xi-v0.0.69-macos-x86_64.tar.gz"
      sha256 "97b5a9c45b41cea9c28dcd8fbf1bd44284967654452b9b5269e5ef16ab42523c"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.69/xi-v0.0.69-linux-arm64.tar.gz"
      sha256 "48d344b8b2738f4572495b19ef036bd4f15431e7526b39b8913cfd299c22330d"
    end
    on_intel do
      url "https://github.com/code-by-sia/x/releases/download/v0.0.69/xi-v0.0.69-linux-x86_64.tar.gz"
      sha256 "346dd5cdf912ef41b94ad58b947bdb96c763b9262f82fadfee30b578d0715939"
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
