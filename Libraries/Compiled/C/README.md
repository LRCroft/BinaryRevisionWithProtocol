# VSN C - distributable

## Files to copy
libvsn.a, libvsn.so, vsn.h (+vsn.c source)

## Consume
Copy to project; include vsn.h; link -lvsn or the .a.

## Dependencies / runtime
gcc toolchain; links pthread.

## Minimal example (public API)
```
vsn_create/create_file/read_file/commit; SP 1..4 via create_with_policy.
```

## Verify
```
gcc main.c libvsn.a -I. -lpthread && ./a.out
```
