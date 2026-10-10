# VSN Python - distributable

## Files to copy
vsn/ package

## Consume
Copy vsn/ onto sys.path; import vsn.

## Dependencies / runtime
python 3.11+.

## Minimal example (public API)
```
VsnStore.create/to_bytes/validate/StoragePolicy; SP 1..4.
```

## Verify
```
python consumer.py (see Consumer/Python)
```
