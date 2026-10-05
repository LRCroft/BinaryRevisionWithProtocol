FROM debian:bookworm
RUN apt-get update -qq && apt-get install -y -qq lua5.4 lua5.4-dev && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV PATH=/usr/bin:$PATH
RUN ln -sf /usr/bin/lua5.4 /usr/local/bin/lua
CMD ["lua"

