# VSN Objective-C conformance test base image
# Built from Ubuntu 24.04 with gcc (ObjC), libobjc, and pthread support
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gobjc \
        libobjc-13-dev \
        libc6-dev \
        libpthread-stubs0-dev \
    && rm -rf /var/lib/apt/lists/*

# gcc (gobjc) includes ObjC support via -x objective-c
# Runtime: libobjc4 provides the ObjC runtime
CMD ["gcc", "--version"]

