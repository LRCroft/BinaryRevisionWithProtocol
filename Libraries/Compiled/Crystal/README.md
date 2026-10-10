# VSN Crystal - distributable

## Files to copy
vsn.cr, shard.yml

## Consume
Copy; require "./vsn.cr".

## Dependencies / runtime
crystal.

## Minimal example (public API)
```
StoreWithPolicy/parse_sp; SP 1..4.
```

## Verify
```
crystal run consumer.cr
```
