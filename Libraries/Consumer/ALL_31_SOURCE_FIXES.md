# VSN ALL-31 Source Fixes — 2026-10-10

Source changes made for canonical Storage Policy verification. **No protocol artifacts modified; no frozen vectors touched.**

## This session (canonical SP verification & obsolete-mapping removal)

| Language | File | Before | After |
|----------|------|--------|-------|
| C | `test_vsn.c` | P02 asserted obsolete `HV→MODERN` / `H→ENTERPRISE` wire-mode inference | Loop over SP 1-4; commit each and assert `parse_sp_value` returns the exact u8 (1-4) |
| C | `vsn.c` | Comments labelled SP as "MODERN/ENTERPRISE mode" | Semantic labels removed; `MODE_MODERN`/`MODE_ENTERPRISE` kept only as binary wire constants |
| Ada | `test_vsn.adb` | Dead `m1-m4` vars with `HV→MODERN` / `H→ENTERPRISE` mapping comments | Removed dead mapping vars; kept the correct SP 1-4 `Get_Storage_Policy` assertion |
| D | `test_vsn.d` | — (verified) | Re-verified: `spRecordValue()` record-walker + 19/19 CAP + SP PASS (Docker `vsn-d:latest`) |

## Prior audit-cycle fixes carried into this state

| Language | File | Fix | Regression |
|----------|------|-----|------------|
| Rust | `Cargo.toml` | crate `Rust` → `vsn-rust` + explicit `[lib] name=vsn_rust path=src/lib.rs` | `cargo test` 19/19 + SP PASS; consumer 9/9 |
| JavaScript-TypeScript | `package.json` | ESM-only → CommonJS/Node16, `exports`/`types`/`files`, multi-platform esbuild | conformance 19/19; consumer CJS 20/20 + ESM 5/5 |

## Invariants preserved
- Wire mode registry `0x01 MODERN` / `0x02 ENTERPRISE` UNTOUCHED (2 normative wire modes).
- `REC_STORAGE_POLICY` (0x0009) / `FID_STORAGE_POLICY` (0x0901) authoritative on wire; payload u8 in {1,2,3,4}.
- Frozen vectors 5/5 SHA-256 MATCH `corpus/manifest.json`.
- Zero active `policyToMode` / `mode_from_storage_policy` / `Mode_From_Policy` mappings remain in library sources.

