#!/bin/bash
cd /work/Libraries/Kotlin
mkdir -p /opt/kotlin-libs
cp /opt/kotlinc/lib/*.jar /opt/kotlin-libs/ 2>/dev/null || true
CP=$(ls /opt/kotlin-libs/*.jar 2>/dev/null | tr "\n" ":")./test.jar
echo "Classpath length: $(echo $CP | wc -c)"
java -ea -cp "$CP" vsn.TestVsn
