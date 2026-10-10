# VSN CSharp - distributable

## Files to copy
Vsn.dll, *.cs sources, Vsn.csproj

## Consume
Reference Vsn.dll or Vsn.csproj.

## Dependencies / runtime
.NET 10 SDK.

## Minimal example (public API)
```
VsnStore.Create/Commit/Validate/Recover/Create(StoragePolicy); SP 1..4.
```

## Verify
```
dotnet run (see Consumer/CSharp)
```
