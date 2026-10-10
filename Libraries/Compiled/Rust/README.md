# VSN Rust - distributable

## Files to copy
libvsn_rust.rlib, src/, Cargo.toml

## Consume
Path dependency vsn-rust; use vsn_rust::*.

## Dependencies / runtime
cargo.

## Minimal example (public API)
```
MutableStore/encode/parse/StoragePolicy; SP 1..4.
```

## Verify
```
cargo run (see Consumer/Rust)
```
