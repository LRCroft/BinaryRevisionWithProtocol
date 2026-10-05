FROM eclipse-temurin:21-jdk
# One JVM image serves Java, Kotlin and Scala. No Docker Hub images exist for
# kotlinc, so install the official compiler release archive.
ARG KOTLIN_VER=1.9.24
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip \
    && curl -fsSL -o /tmp/kt.zip \
      "https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VER}/kotlin-compiler-${KOTLIN_VER}.zip" \
    && unzip -q /tmp/kt.zip -d /opt && rm /tmp/kt.zip \
    && ln -s /opt/kotlinc/bin/kotlinc /usr/local/bin/kotlinc \
    && rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/kotlinc/bin:${PATH}"
WORKDIR /work