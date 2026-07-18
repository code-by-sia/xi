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
  version "0.1.3"
  license "Apache-2.0"

  on_macos do
    on_arm do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.3/xi-v0.1.3-macos-arm64.tar.gz"
      sha256 "25c0ba3a5eab5d98c847d3fd177d1f807d03f461f86bd12dce282834b03be44c"
    end
    on_intel do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.3/xi-v0.1.3-macos-x86_64.tar.gz"
      sha256 "526150a28666021cbbce6765be0324154b87916760918cb5bbe134c2e0d33ac3"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.3/xi-v0.1.3-linux-arm64.tar.gz"
      sha256 "574c9627b901c33feb7ed1dc77010824f7c8b1de72c1a5635b38c3e0148cd10c"
    end
    on_intel do
      url "https://github.com/code-by-sia/xi/releases/download/v0.1.3/xi-v0.1.3-linux-x86_64.tar.gz"
      sha256 "0ff8dde7cfba346e99a5fce7a4998fa8741758a6b21b12ef0239a2019e416b94"
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
