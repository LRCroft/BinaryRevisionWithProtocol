# VSN JavaScript-TypeScript - distributable

## Files to copy
dist/ (JS + .d.ts), src/, package.json (CJS)

## Consume
npm install <dir>; require() the package.

## Dependencies / runtime
node 20.

## Minimal example (public API)
```
VsnStore/commit/parse/StoragePolicy; SP 1..4.
```

## Verify
```
node consumer.cjs (see Consumer/JS-TS)
```
