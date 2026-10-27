# Build environment for upstream Lean 4 (doc/make/ubuntu.md), plus perf tooling for benchmarks.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      git libgmp-dev libuv1-dev libssl-dev cmake ccache clang lld pkgconf make python3 \
      ca-certificates time util-linux zstd \
    && rm -rf /var/lib/apt/lists/*
ARG UID=1001
ARG GID=1001
RUN (getent group $GID || groupadd --gid $GID builder) && useradd --uid $UID --gid $GID --create-home builder || true
USER $UID:$GID
