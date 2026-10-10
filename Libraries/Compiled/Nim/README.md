# VSN Nim - distributable

## Files to copy
libvsnnim.a, vsn.nim

## Consume
Copy; import vsn or link .a.

## Dependencies / runtime
nim.

## Minimal example (public API)
```
encodeWithSP/importBytes/exportStoragePolicy; SP 1..4.
```

## Verify
```
nim c -r consumer.nim
```
