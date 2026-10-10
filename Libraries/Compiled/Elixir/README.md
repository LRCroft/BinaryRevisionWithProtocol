# VSN Elixir - distributable

## Files to copy
Elixir.VSN.beam, Elixir.VSN.MutableStore.beam, vsn.ex

## Consume
Copy .beam files or Code.require vsn.ex.

## Dependencies / runtime
elixir 1.17.

## Minimal example (public API)
```
VSN.encode/3 + parse; SP 1..4.
```

## Verify
```
elixir consumer.exs
```
