FROM debian:bookworm
# Zig has no usable Docker Hub image; install from the official release tarball.
ARG ZIG_VER=0.13.0
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils \
    && curl -fsSL "https://ziglang.org/download/${ZIG_VER}/zig-linux-x86_64-${ZIG_VER}.tar.xz" -o /tmp/zig.tar.xz \
    && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz && ln -s /opt/zig/zig /usr/local/bin/zig \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work