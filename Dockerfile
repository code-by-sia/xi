# Run the Xi toolchain in a container — handy on Windows (no native build needed).
#
#   docker build -t xi .
#   # compile + run a program (mount your code at /work):
#   docker run --rm -v "${PWD}:/work" xi xi hello.xi
#   # just compile (-> /work/build/hello):
#   docker run --rm -v "${PWD}:/work" xi xc hello.xi
#   # interactive REPL:
#   docker run --rm -it -v "${PWD}:/work" xi xi
#
# PowerShell uses ${PWD}; cmd.exe uses %cd%.
#
# The image downloads a published Xi release from GitHub and puts `xc` (compiler)
# and `xi` (REPL / run tool) on PATH. A C compiler (gcc/cc) is included because
# `xc` shells out to `cc` to produce the native binary.
FROM debian:stable-slim

# Pin a release with --build-arg XI_VERSION=vX.Y.Z; default is the latest release.
ARG XI_VERSION=latest
ARG XI_REPO=code-by-sia/xi
# Docker buildx sets TARGETARCH automatically (amd64 / arm64).
ARG TARGETARCH=amd64

RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev curl ca-certificates tar \
 && rm -rf /var/lib/apt/lists/* \
 && [ -e /usr/bin/cc ] || ln -s "$(command -v gcc)" /usr/bin/cc

RUN set -eux; \
    case "$TARGETARCH" in \
        amd64) arch=x86_64 ;; \
        arm64) arch=arm64  ;; \
        *) echo "unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    if [ "$XI_VERSION" = "latest" ]; then \
        ver="$(curl -fsSL "https://api.github.com/repos/${XI_REPO}/releases/latest" \
               | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1)"; \
    else ver="$XI_VERSION"; fi; \
    [ -n "$ver" ] || { echo "could not resolve a release version" >&2; exit 1; }; \
    echo "Installing Xi $ver (linux-$arch)"; \
    base="https://github.com/${XI_REPO}/releases/download/${ver}"; \
    # newer releases use the "xi-" artifact prefix; fall back to the legacy "x-".
    if curl -fsSL "${base}/xi-${ver}-linux-${arch}.tar.gz" -o /tmp/xi.tgz; then \
        tar -xzf /tmp/xi.tgz -C /opt; mv "/opt/xi-${ver}-linux-${arch}" /opt/xi; \
    else \
        curl -fsSL "${base}/x-${ver}-linux-${arch}.tar.gz" -o /tmp/xi.tgz; \
        tar -xzf /tmp/xi.tgz -C /opt; mv "/opt/x-${ver}-linux-${arch}" /opt/xi; \
    fi; \
    rm -f /tmp/xi.tgz; \
    # older bundles ship bin/x; expose it as `xi` too (relative symlink keeps the
    # wrapper's bundle-relative path resolution intact).
    [ -e /opt/xi/bin/xi ] || ln -s x /opt/xi/bin/xi; \
    /opt/xi/bin/xc >/dev/null 2>&1 || true

# Putting the bundle's bin/ on PATH (rather than symlinking elsewhere) lets the
# wrappers locate the bundle and set XC_RUNTIME / XC_STD relative to themselves.
ENV PATH="/opt/xi/bin:${PATH}"
WORKDIR /work
CMD ["xi"]
