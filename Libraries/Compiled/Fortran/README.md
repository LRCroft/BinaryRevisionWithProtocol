# VSN Fortran - distributable

## Files to copy
libvsnfortran.a, vsn.f90, vsn_mod.mod

## Consume
Copy; compile with vsn.f90 or link .a + .mod.

## Dependencies / runtime
gfortran.

## Minimal example (public API)
```
vsn_create_with_policy/vsn_encode/vsn_parse_storage_policy; SP 1..4.
```

## Verify
```
gfortran -c vsn.f90 && gfortran main.f90 vsn.o && ./a.out
```
