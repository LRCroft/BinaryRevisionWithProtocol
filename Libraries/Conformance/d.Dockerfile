FROM vsn-d:latest
RUN apt-get update -qq && apt-get install -y --no-install-recommends gcc libc6-dev && rm -rf /var/lib/apt/lists/*
RUN ln -sf /usr/bin/gcc /usr/bin/cc 2>/dev/null || true
WORKDIR /work
CMD ["/bin/bash"]
