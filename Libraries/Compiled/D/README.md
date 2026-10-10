# VSN D - distributable

## Files to copy
libvsnd.a, vsn_d.o, vsn.d, dub.json

## Consume
Copy; compile with vsn.d or link .a.

## Dependencies / runtime
dmd 2.109.

## Minimal example (public API)
```
createWithPolicy/exportBytes/importBytes; SP 1..4.
```

## Verify
```
dmd consumer.d vsn.d -of=c && ./c
```
