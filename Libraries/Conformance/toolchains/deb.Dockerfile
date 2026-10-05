# VSN conformance toolchains, built as Docker images.
#
# Each image carries a real compiler/interpreter for one or more VSN library
# targets so that conformance is decided by EXECUTING the language's own test
# suite, never by inspecting source text.
#
# Coverage:
#   vsn-deb    - Ada(GNAT), Fortran(gfortran), D(gdc), OCaml, Haskell(GHC),
#                Erlang, Elixir, Crystal, Nim, Lua, Objective-C(GNUstep/gobjc),
#                COBOL(GnuCOBOL)
#   vsn-jvm    - Java, Kotlin, Scala
#
# Single-language images (golang, rust, julia, r-base, dart, php, ruby, perl,
# swift) are pulled directly by the conformance runner.

FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git curl unzip \
        python3 \
        gnat gnat-12 gfortran gdc \
        ocaml-nox \
        ghc \
        erlang-nox elixir \
        crystal \
        nim \
        lua5.4 \
        gobjc-12 \
        gnustep-devel gnustep-base-runtime libgnustep-base-dev \
        gnucobol4 \
        default-jdk-headless \
        maven \
    && rm -rf /var/lib/apt/lists/*

# Kotlin and Scala toolchains are downloaded by the runner scripts so the image
# stays cacheable; these directories hold the unpacked distributions.
RUN mkdir -p /opt/tools
ENV KOTLIN_HOME=/opt/tools/kotlin
ENV SCALA_HOME=/opt/tools/scala

CMD ["/bin/bash"]