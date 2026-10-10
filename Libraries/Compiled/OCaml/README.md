# VSN OCaml - distributable

## Files to copy
vsn.cma, vsn_ocaml.cmo, vsn.cmi, vsn.ml

## Consume
Copy; link vsn.cma or compile alongside.

## Dependencies / runtime
ocamlc.

## Minimal example (public API)
```
encode_with_policy/parse; SP 1..4.
```

## Verify
```
ocamlc vsn.ml consumer.ml -o c && ./c
```
