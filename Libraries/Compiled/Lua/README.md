# VSN Lua - distributable

## Files to copy
vsn.lua

## Consume
Copy; require "vsn" with package.path.

## Dependencies / runtime
lua.

## Minimal example (public API)
```
create_with_storage_policy/to_bytes/open; SP 1..4.
```

## Verify
```
lua consumer.lua (canonical layout)
```
