# VSN Scala - distributable

## Files to copy
vsn-scala.jar, vsn.scala

## Consume
Copy jar; scala-cli or java -cp jar.

## Dependencies / runtime
Scala 3.9.

## Minimal example (public API)
```
VsnApi.encodeWithSP/parseSP; SP 1..4.
```

## Verify
```
scala-cli run vsn.scala consumer.scala
```
