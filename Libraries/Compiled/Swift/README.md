# VSN Swift - distributable

## Files to copy
VSN.swiftmodule, VSN.swiftdoc, Vsn.swift, Package.swift

## Consume
Copy into SPM package or compile Vsn.swift alongside.

## Dependencies / runtime
swift 5.9.

## Minimal example (public API)
```
VsnApi.encode/parseStoragePolicy; SP 1..4.
```

## Verify
```
swiftc Vsn.swift main.swift -o c && ./c
```
