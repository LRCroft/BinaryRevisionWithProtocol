# VSN COBOL - distributable

## Files to copy
vsn_lib.cbl (+vsn_lib.o)

## Consume
Copy; CALL VSN-LIBRARY with op codes.

## Dependencies / runtime
GnuCOBOL.

## Minimal example (public API)
```
op29/30 set/get; op18/19 export/import; SP 1..4.
```

## Verify
```
cobc -x -free consumer.cbl vsn_lib.cbl -o c && ./c
```
