# VSN FSharp - distributable

## Files to copy
Vsn.dll, Vsn.fs, Vsn.fsproj

## Consume
Reference Vsn.dll or Vsn.fsproj.

## Dependencies / runtime
.NET 10 SDK.

## Minimal example (public API)
```
Vsn.encode/parse + StoragePolicy; SP 1..4.
```

## Verify
```
dotnet run (see Consumer/FSharp)
```
