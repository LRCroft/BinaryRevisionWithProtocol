// VSN-1 Architecture Change: Storage Policy Protocol Migration
# Date: 2026-10-08 Act Mode

## Summary

This change implements the architectural shift in VSN-1 storage policy classification:

### New Constants (Authoritative, Directly on Wire)

| Constant | Value | Description |
|----------|-------|-------------|
| `REC_STORAGE_POLICY` | `0x0009` | StoragePolicy record type identifier (new normative wire record) |
| `FID_STORAGE_POLICY` | `0x0901` | StoragePolicy.field_id for identity records |

### Deprecated Constants (Kept for Backward Reader Compatibility)

| Constant | Value | Status |
|----------|-------|--------|
| `MODE_MODERN` | `1` | OBSOLETE: was MODERN wire mode |
| `MODE_ENTERPRISE` | `2` | OBSOLETE: was ENTERPRISE wire mode |
| `REC_MODE_DECLARATION` | `0x0007` | OBSOLETE: deprecated, kept for reader compatibility only |

### Storage Policy Profiles (Authoritative Classification)

All storage policy values are now the **authoritative classification** directly on wire. Old comments about "informative, NOT on wire" have been replaced with "authoritative classification".

| Profile | Value | Maps To Wire Mode |
|---------|-------|-------------------|
| HIGHLY_VERTICAL | 1 | MODERN (0x01) |
| VERTICAL | 2 | MODERN (0x01) |
| HORIZONTAL | 3 | ENTERPRISE (0x02) |
| HIGHLY_HORIZONTAL | 4 | ENTERPRISE (0x02) |

## Files Changed

All 31 language libraries updated:

- Ada (vsn.ads, vsn.adb)
- C (vsn.h)
- COBOL (vsn_lib.cbl)
- C# (Vsn/Constants.cs, Vsn/StoragePolicy.cs)
- C++ (vsn.hpp)
- Crystal (vsn.cr)
- D (vsn.d)
- Dart (vsn.dart)
- Elixir (vsn.ex)
- Erlang (vsn.erl)
- F# (Vsn/Vsn.fs)
- Fortran (vsn.f90)
- Go (constants.go)
- Haskell (VSN.hs)
- Java (VsnLib.java)
- JavaScript/TypeScript (src/constants.ts)
- Julia (vsn.jl)
- Kotlin (Vsn.kt)
- Lua (vsn.lua)
- Nim (vsn.nim)
- Objective-C (VSN.h - created)
- OCaml (vsn.ml)
- Perl (vsn.pl)
- PHP (vsn.php)
- Python (vsn/constants.py)
- R (vsn.R)
- Ruby (vsn.rb)
- Rust (src/lib.rs)
- Scala (vsn.scala)
- Swift (Vsn.swift)
- Zig (vsn.zig)

## Conformance Files Updated

- `Libraries/Conformance/corpus/storage_policy/canonical_policy_matrix.json`
- `Libraries/Conformance/corpus/storage_policy/fixtures_p01_p06.json`
- `Libraries/Conformance/corpus/storage_policy/fixtures_p07_p12.json`

## Verification Status

**31/31 languages verified**: REC_STORAGE_POLICY = 0x0009 and FID_STORAGE_POLICY = 0x0901 present in all implementations.

All MODE_ constants marked as OBSOLETE/deprecated where they appear in library source files. Test files retain the values for backward compatibility testing.

