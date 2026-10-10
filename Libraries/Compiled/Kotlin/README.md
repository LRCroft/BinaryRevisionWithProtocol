# VSN Kotlin - distributable

## Files to copy
vsn-kotlin.jar, Vsn.kt

## Consume
Copy jar; kotlinc/java -cp jar.

## Dependencies / runtime
kotlinc.

## Minimal example (public API)
```
VsnApi.encode/parse/parseStoragePolicy; SP 1..4.
```

## Verify
```
kotlinc Vsn.kt main.kt -include-runtime -d c.jar && java -jar c.jar
```
