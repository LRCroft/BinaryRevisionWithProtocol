FROM debian:bookworm
# One shared legacy toolchain image serves Ada (GNAT), Fortran (gfortran),
# COBOL (GnuCOBOL) and Objective-C (GNU Objective-C). Builds once, reused by all.
RUN apt-get update && apt-get install -y --no-install-recommends \
      gnat gnat-12 gfortran gnucobol gobjc make \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work