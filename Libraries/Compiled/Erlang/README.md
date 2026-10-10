# VSN Erlang - distributable

## Files to copy
vsn.beam, vsn.erl, rebar.config

## Consume
Copy .beam onto code path, or compile vsn.erl.

## Dependencies / runtime
erlc/erl.

## Minimal example (public API)
```
vsn:encode/3 + parse; SP 1..4.
```

## Verify
```
erlc consumer.erl vsn.erl && erl -noshell -s consumer main -s init stop
```
