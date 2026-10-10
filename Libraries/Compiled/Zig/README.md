# VSN Zig - distributable

## Files to copy
libvsnzig.a, vsn.zig, build.zig

## Consume
Copy; add as module or link .a.

## Dependencies / runtime
zig.

## Minimal example (public API)
```
encode/parseStoragePolicy; SP 1..4.
```

## Verify
```
zig run consumer.zig
```
