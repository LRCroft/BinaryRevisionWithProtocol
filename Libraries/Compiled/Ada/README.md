# VSN Ada - distributable

## Files to copy
vsn.adb, vsn.ads (+vsn.ali/vsn.o)

## Consume
Copy all four into GNAT project dir.

## Dependencies / runtime
GNAT.

## Minimal example (public API)
```
Create_With_Policy/Export_Bytes/Import_Bytes/Get_Storage_Policy; SP 1..4.
```

## Verify
```
gnatmake main.adb && ./main
```
