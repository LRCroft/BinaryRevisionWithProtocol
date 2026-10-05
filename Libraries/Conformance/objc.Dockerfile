FROM gcc:13
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        gobjc-11 libobjc-11-dev gobjc++-11 \
    && rm -rf /var/lib/apt/lists/*
# Create gobjc symlink
RUN ln -sf /usr/bin/gcc-11 /usr/bin/gobjc-11 2>/dev/null || true
# Verify ObjC support
RUN echo "int main(){ return 0; }" > /tmp/t.m && \
    gcc-11 -x objective-c -lobjc /tmp/t.m -o /tmp/t && /tmp/t && rm -f /tmp/t /tmp/t.m
WORKDIR /work
CMD ["/bin/bash"]
