# VSN Objective-C - distributable

## Files to copy
libvsnobjc.a, libvsnobjc.so, VSN.h, vsn_sp_c.c, VSN.m

## Consume
Copy; #import VSN.h or compile vsn_sp_c.c alongside.

## Dependencies / runtime
gcc; vsn-objc image.

## Minimal example (public API)
```
vsn_sp_encode_c/vsn_sp_parse_c; SP 1..4.
```

## Verify
```
gcc consumer.c vsn_sp_c.c -o c && ./c
```
