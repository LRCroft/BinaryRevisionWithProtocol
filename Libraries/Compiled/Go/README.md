# VSN Go - distributable

## Files to copy
*.go module sources, go.mod

## Consume
Copy module dir; replace/require from your module.

## Dependencies / runtime
go 1.22+.

## Minimal example (public API)
```
Create/CreateWithPolicy/commit/Parse/Open; SP 1..4.
```

## Verify
```
go run . with replace (see Consumer/Go)
```
