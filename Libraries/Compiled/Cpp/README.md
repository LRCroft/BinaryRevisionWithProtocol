# VSN Cpp - distributable

## Files to copy
libvsncpp.a, libvsncpp.so, vsn.hpp (+vsn.cpp; needs C libvsn)

## Consume
Copy; include vsn.hpp; link libvsncpp + libvsn.

## Dependencies / runtime
g++ C++17.

## Minimal example (public API)
```
create_with_storage_policy_raw/commit/open; SP 1..4.
```

## Verify
```
g++ main.cpp libvsncpp.a libvsn.a -I. && ./a.out
```
