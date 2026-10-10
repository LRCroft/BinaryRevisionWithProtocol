# VSN Haskell - distributable

## Files to copy
libvsnhaskell.a, VSN.o, VSN.hi, VSN.hs

## Consume
Copy; compile with VSN.hs or link .a.

## Dependencies / runtime
ghc.

## Minimal example (public API)
```
createWithPolicy/exportBytes/parse; SP 1..4.
```

## Verify
```
ghc Main.hs && ./Main
```
