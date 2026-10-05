FROM debian:bookworm
# DMD has no usable Docker Hub image; install via the official dlang.org script.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget xz-utils \
    && update-ca-certificates \
    && curl -fsSL https://dlang.org/install.sh -o /tmp/install.sh \
    && bash /tmp/install.sh dmd-2.109.1 -p /usr/local \
    && ln -sf /usr/local/dmd/bin/* /usr/local/bin/ \
    && ln -sf /usr/local/dmd/src/* /usr/local/src/ 2>/dev/null || true \
    && rm -f /tmp/install.sh /usr/local/install.sh && rm -rf /var/lib/apt/lists/*
ENV PATH="/usr/local/dmd-2.109.1/linux/bin64:${PATH}"
ENV DMD="/usr/local/dmd-2.109.1/linux/bin64/dmd"
WORKDIR /work