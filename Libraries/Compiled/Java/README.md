# VSN Java - distributable

## Files to copy
vsn-java.jar, VsnLib.java

## Consume
Copy jar; javac/java -cp vsn-java.jar.

## Dependencies / runtime
java 17+.

## Minimal example (public API)
```
Store.create/commit/parseStoragePolicy/createWithPolicy; SP 1..4.
```

## Verify
```
javac -cp vsn-java.jar Main.java && java -cp .:vsn-java.jar Main
```
