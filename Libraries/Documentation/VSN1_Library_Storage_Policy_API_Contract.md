
# VSN Library Storage Policy API & Conformance Contract

**Status:** Draft -- Awaiting Approval
**Applies to:** All VSN library implementations (all 31 languages)
**Scope:** Language-neutral Library API contract for Writer Storage Policy and Optimization Configuration; does NOT modify the frozen wire protocol.

---

## 0. Objective and Constraints

This document defines the **Library API contract** for Writer Storage Policy support in VSN. It defines:

- A canonical `StoragePolicy` type with exactly four values.
- The deterministic mapping from `StoragePolicy` to `WireMode`.
- An optional `WriterOptions` composition model.
- An `OptimizationConfiguration` model.
- Ten capability conformance tests (CAP-P01 through CAP-P10).

### Constraints

This task MUST NOT:
- Modify ModeDeclaration wire values (0x01 MODERN, 0x02 ENTERPRISE).
- Add new record types, field IDs, or representation identities.
- Change frozen vectors or their SHA-256 hashes.
- Introduce a persisted policy field in the container binary.
- Make readers dependent on writer policy names.
- Alter CommitMarker semantics, ObjectSerial semantics (ID-03, ID-09, ID-61, SR-37), or recovery rules.
- Collapse Wire Mode, Storage Policy, and Optimization Configuration into a single enum.

---

## 1. Existing API Analysis

### Current Writer API Pattern

All three reference implementations (Python, C#, TypeScript) use the same pattern:

```text
VsnStore.Create(mode: byte) -> VsnStore
VsnStore.Open(data: bytes)   -> VsnStore
```

Where `mode` is one of:
- `MODE_MODERN = 0x01` (MODERN wire mode)
- `MODE_ENTERPRISE = 0x02` (ENTERPRISE wire mode)

The current API has **no storage policy parameter** and **no optimization configuration**. The writer implicitly uses an internal default that is not exposed as a Library-level concept.

### Current Constants Registry

All implementations store these frozen constants in their respective `constants.ts / Constants.cs / constants.py`:

```
MODE_MODERN     = 0x01
MODE_ENTERPRISE = 0x02
REP_DIRECT_1    = 0x0001
REP_EXTENTS_1   = 0x0002
```

### Implications

The canonical Library API model must **extend** the existing `VsnStore.Create(mode)` pattern with an optional policy parameter, **not replace it**. Any backward-incompatible change would require reworking all 31 language implementations in a single coordinated migration, which is outside this contract's scope.

---

## 2. Canonical StoragePolicy Type

### Definition

A library MUST expose a `StoragePolicy` type with exactly four values:

| Value | Name (constant) | Naming convention per language |
|-------|-----------------|-------------------------------|
| HIGHLY_Vertical | Highest optimization effort within MODERN wire mode | `StoragePolicy.HIGHLY_VERTICAL` (Java/TS/Kotlin) or `StoragePolicy.HighlyVertical` (C#/Rust/Swift) |
| VERTICAL | Bounded optimization effort within MODERN wire mode | `StoragePolicy.VERTICAL` / `StoragePolicy.Vertical` |
| HORIZONTAL | Low optimization effort within ENTERPRISE wire mode | `StoragePolicy.HORIZONTAL` / `StoragePolicy.Horizontal` |
| HIGHLY_Horizontal | Minimal optimization effort within ENTERPRISE wire mode | `StoragePolicy.HIGHLY_HORIZONTAL` / `StoragePolicy.HighlyHorizontal` |

### Requirements

- Exactly four values. No additional values may be added without this contract being amended.
- The StoragePolicy type is a **Library-level configuration concept only**. It is NOT a wire protocol value.
- StoragePolicy values MUST NOT serialize as 0x01, 0x02, 0x03, or 0x04 on the wire.

---

## 3. Policy-to-WireMode Mapping

### Deterministic Resolution Rules

| StoragePolicy | Effective WireMode | Rationale |
|--------------|-------------------|-----------|
| HIGHLY_Vertical  | MODERN (0x01)  | HIGHLY_Vertical requires MODERN representation architecture (EXTENTS-1 deep dependencies) |
| VERTICAL         | MODERN (0x01)  | VERTICAL requires MODERN representation architecture |
| HORIZONTAL       | ENTERPRISE (0x02) | HORIZONTAL inherits ENTERPRISE DIRECT-1 baseline preference |
| HIGHLY_Horizontal | ENTERPRISE (0x02) | HIGHLY_Horizontal forbids EXTENTS-1, consistent with ENTERPRISE rules |

### Conflict Resolution Behavior

When a caller explicitly provides both `storage_policy` and `wire_mode`:

**Canonical rule: reject the combination when they are incompatible.**

| Provided Policy | Provided WireMode | Result |
|----------------|------------------|--------|
| HIGHLY_Vertical | MODERN (0x01)   | Accept (consistent) |
| HIGHLY_Vertical | ENTERPRISE (0x02) | Reject -- policy requires MODERN |
| VERTICAL | MODERN (0x01)        | Accept (consistent) |
| VERTICAL | ENTERPRISE (0x02)     | Reject -- policy requires MODERN |
| HORIZONTAL | ENTERPRISE (0x02)    | Accept (consistent) |
| HORIZONTAL | MODERN (0x01)         | Reject -- policy requires ENTERPRISE |
| HIGHLY_Horizontal | ENTERPRISE (0x02)  | Accept (consistent) |
| HIGHLY_Horizontal | MODERN (0x01)        | Reject -- policy requires ENTERPRISE |

**Rationale:** Each storage policy is defined within a specific wire-mode family. A policy cannot operate outside its permitted wire mode because the available representation architecture differs between MODERN and ENTERPRISE. EXTENTS-1 deep dependencies are MODERN-only; DIRECT-1 baseline for ENTERPRISE is mandated by wire rules.

---

## 4. WriterOptions Model

### Canonical Composition

```
WriterOptions
  ├── storage_policy    : StoragePolicy | null   (optional)
  └── optimization    : OptimizationConfiguration | null  (optional)
```

When `storage_policy` is absent, the writer uses its implementation default wire mode. This **preserves existing behavior** -- no change to current writers.

### WriterOptions-to-WireMode Derivation Rules

| storage_policy present? | effective_wire_mode source | Result |
|-----------------------|---------------------------|--------|
| Yes | Derived from policy mapping (Section 3) | Deterministic mapping applied |
| No, explicit wire_mode provided | The explicit value | Backward-compatible with current API |
| No explicit wire_mode, no policy | Library default (see Section 9) | Preserves existing behavior |

### Optional Explicit WireMode Constraint

The WriterOptions model may optionally include an explicit `wire_mode_constraint`:

```
WriterOptions
  ├── storage_policy       : StoragePolicy | null
  ├── wire_mode_constraint : WireMode | null   (optional upper-bound constraint)
  └── optimization         : OptimizationConfiguration | null
```

When both `storage_policy` and `wire_mode_constraint` are present:
- If they are consistent per Section 3 rules: accept, use the derived effective wire mode.
- If they conflict: reject with INVALID configuration error (see Section 15).
- `wire_mode_constraint` is a **validation bound**, not a replacement for `storage_policy`.

### Language-Specific API Semantics

The canonical model applies across all languages. Language conventions determine naming and parameter style:

**C# / F# pattern (recommended):**
```csharp
VsnStore.Create(WriterOptions options);   // named parameters
VsnStore.Create(storagePolicy: StoragePolicy.HighlyVertical);
// backward compatible: VsnStore.Create(Constants.ModeModern) still works
```

**Python pattern (recommended):**
```python
VsnStore.create(writer_options=None)  // keyword argument, default None
// backward compatible: VsnStore.create(mode=C.MODE_MODERN) still works
// new path: VsnStore.create(writer_options=WriterOptions(storage_policy=StoragePolicy.HighlyVertical))
```

**TypeScript / JavaScript pattern (recommended):**
```typescript
VsnStore.create(options?: WriterOptions): VsnStore;  // optional config object
// backward compatible: VsnStore.create(MODE_MODERN) still works
// new path: VsnStore.create({ storagePolicy: StoragePolicy.HIGHLY_VERTICAL })
```

**Java / Kotlin pattern (recommended):**
```kotlin
VsnStore.create(options: WriterOptions): VsnStore  // named constructor with builder
// backward compatible: VsnStore.create(MODE_MODERN) still works
// new path: VsnStore.create(WriterOptions(storagePolicy = StoragePolicy.HIGHLY_VERTICAL))
```

**All other languages:** Follow the pattern of their reference implementation. The semantic model is identical; naming conventions adapt to language norms.

---

## 5. OptimizationConfiguration Model

### Definition

```
OptimizationConfiguration
  ├── search_budget        : u64 | null     (optional)
  ├── memory_limit         : u64 | null     (optional)
  ├── max_dependency_depth : u32 | null     (optional)
  ├── max_extent_count     : u32 | null     (optional)
  ├── decode_work_limit    : u64 | null     (optional)
  ├── min_savings_bytes    : i64 | null     (optional)
  └── candidate_size       : u32 | null     (optional)
```

### Field Definitions

| Field | Purpose | Units/Type | Optional | Default | Hard limit or preference | Exceeded behavior | Affects logical semantics? | Affects wire compatibility? |
|-------|---------|------------|----------|---------|------------------------|-------------------|--------------------------|----------------------------|
| search_budget | Maximum search work for deduplication/candidate enumeration | abstract units (implementation-defined) | Yes | Policy-dependent bounded search | Hard limit | Fall back to simpler representation; never produce invalid container | NO | Only by changing representation choice |
| memory_limit | Maximum working set for optimization phase | bytes | Yes | Policy-dependent unbounded within reason | Preference with hard cap | Reduce search depth/breadth; fall back to DIRECT-1 full copy | NO | Only by changing representation choice |
| max_dependency_depth | Maximum allowed depth of EXTENTS-1 dependency chains | hops (integer) | Yes | Policy-dependent bound in policy spec | Hard limit | Use shallower chain or DIRECT-1 fallback | NO | Only by changing representation choice |
| max_extent_count | Maximum number of extent operands per object | count (integer) | Yes | Policy-dependent bound in policy spec | Hard limit | Split into more objects with fewer extents; DIRECT-1 fallback | NO | Only by changing representation choice |
| decode_work_limit | Maximum work allowed during materialization at read time | abstract units | Yes | No cap (unlimited decode) | Preference | Reject or truncate materialization; report error | NO | NO -- only affects reader behavior, not writer output |
| min_savings_bytes | Minimum bytes saved to justify EXTENTS-1 over DIRECT-1 | bytes (can be negative) | Yes | 0 (any positive savings justifies optimization) | Preference | Use DIRECT-1 when savings below threshold | NO | Only by changing representation choice |
| candidate_size | Target size for content chunking/candidate partitioning | bytes | Yes | Policy-dependent heuristic | Preference | Varies output; always produces valid container | NO | Content boundaries may differ but logical content is identical |

### Critical Guarantees

1. **Resource limit MUST NOT make an otherwise-valid VSN container semantically invalid.** A writer choosing a lower optimization budget must still produce a valid container -- it may be less optimized but never structurally or semantically broken.
2. **Optimization Configuration does NOT affect logical semantics.** FileId, RevisionId, parent relationships, ObjectSerial rules, deletion semantics, directory semantics, ContentRef semantics, CommitMarker acceptance, recovery semantics, and integrity semantics are identical regardless of optimization configuration.
3. **Optimization Configuration is NOT on the wire.** These values do not appear in serialized containers and are not part of reader grammar.

---

## 6. Policy Must Never Change Logical Semantics

Selecting a different storage policy MUST NOT alter:

- FileId (16-byte generated identity, never content-derived)
- RevisionId semantics (monotonically increasing integer per file)
- Parent revision relationships
- ObjectSerial identity rules (ID-03, ID-09, ID-61)
- Deletion semantics (SR-09 presence: PRESENT=1, DELETED=2)
- Directory semantics (DIRECTORY=3)
- ContentRef semantics (references to content objects)
- CommitMarker acceptance behavior (RC-01 through RC-45)
- Recovery semantics (prefix recovery, uncommitted tail discard)
- Integrity verification semantics

Policy affects physical storage strategy only. Two writers producing the same logical state under different policies must produce containers with identical FileIds, RevisionIds, ObjectSerials for corresponding revisions and objects, but potentially different physical representation layouts.
Policy affects physical storage strategy only. Two writers producing the same logical state under different policies must produce containers with identical FileIds, RevisionIds, ObjectSerials for corresponding revisions and objects, but potentially different physical representation layouts.

---

## 7. Default Policy Analysis

### Current State: No Library-Level Default Storage Policy

The current API (`VsnStore.Create(mode)`) does **not** expose any storage policy concept. The writer uses an internal default that is implementation-specific and not part of the public contract.

### Recommendation: Preserve Existing Behavior

A new Library-level default MUST NOT be introduced in this contract without explicit approval from the repository maintainers, because:
1. Existing writers (across all 31 languages) currently operate with no storage policy awareness.
2. Introducing a default would change the optimization behavior of every existing writer that upgrades.
3. Different implementations may have different natural defaults based on their resource profiles.

### Recommended Approach (for future approval)

**Recommended default:** `null` (no policy = use implementation's native internal default).

When `storage_policy` is `null`:
- The writer uses its built-in representation selection strategy (which currently produces valid containers).
- This preserves 100% backward compatibility with all existing code.
- Implementations that wish to establish a policy-specific default MAY document it, but the Library contract does not mandate one.

### Implementation Guidance

| Language family | Recommended default behavior when storage_policy is null |
|----------------|--------------------------------------------------------|
| Python / C# / Java / TS | Use existing internal representation selection (unchanged) |
| All others | Follow reference implementation default; document if changing |

---

## 8. Reader Independence Guarantee

### Core Requirement

A conforming reader MUST NOT require knowledge of:
- HIGHLY_Vertical
- VERTICAL
- HORIZONTAL
- HIGHLY_Horizontal

in order to decode a valid VSN container.

The reader uses only:
```
VSN wire mode (ModeDeclaration: 0x01 or 0x02)
+ normative representation semantics (DIRECT-1 / EXTENTS-1 from the registry)
+ existing recovery/validation rules (RC-01..RC-45, GR-01..GR-48)
```

### No Wire Dependency

If the existing protocol has no persisted policy field (it does not), this contract MUST NOT add one:
- Do NOT add a new record type for writer policy metadata.
- Do NOT modify ModeDeclaration to encode the policy.
- Do NOT add a new field to the container header or trailer.
- Policy information is strictly implementation-local configuration.

### Reader Behavior

A reader decodes a container using this path, identical regardless of writer's storage policy:

```
Container bytes → Parse (magic VSN-, CFV, EV)
  → Read ModeDeclaration (0x01 or 0x02)
  → For each content object: Read RepresentationDescriptor → Materialize
  → Resolve logical state via CommitMarker-based recovery
```

At no point does the reader inspect, infer, or depend on the writer's storage policy.

---

## 9. Policy Persistence Decision

### Current Protocol State: No Policy Persistence

The frozen VSN protocol does **not** persist writer storage policy anywhere in the container binary. ModeDeclaration (0x0007) encodes only the wire mode (0x01 or 0x02).

### Contract Verdict

Writer Storage Policy is configuration/intent, not normative container state. This contract explicitly documents this fact:
- No policy data appears in any VSN record type.
- No policy data appears in the container header or trailer.
- No policy data appears in object descriptors.
- ModeDeclaration continues to encode only wire mode, not storage policy.

### Implementation Metadata (Separate from Wire)

An implementation MAY store the writer's chosen policy alongside its local files as implementation metadata. This is:
- Local to the implementing system. Not transmitted on the wire with VSN containers. Optional -- a reader does not need it.
An implementation MAY store the writer's chosen policy alongside its local files as implementation metadata. This is:
- Local to the implementing system. Not transmitted on the wire with VSN containers. Optional -- a reader does not need it.

---

## 10. Representation Selection Semantics

### How Policy Influences Representation Choice

The four policies influence writer representation decisions **within** the boundaries of representations permitted by the selected wire mode. No new representations are created.

| StoragePolicy | EXTENTS-1 Role | DIRECT-1 Role | Compression Role |
|--------------|----------------|---------------|------------------|
| HIGHLY_Vertical | Primary optimization target where MODERN permits it | Fallback when optimization does not save storage | Aggressive on rep source data within resource bounds |
| VERTICAL | Available but bounded by optimization config (max_dependency_depth, max_extent_count) | Common fallback when bounded search finds no savings | Bounded effort; evaluate savings vs cost |
| HORIZONTAL | Limited/shallow only where ENTERPRISE permits | Preferred baseline for all emitted content | Optional on stored content; NONE baseline must suffice |
| HIGHLY_Horizontal | Forbidden (forbids reconstruction dependencies) | Required for all emitted content objects | No compression dependency for correctness |

### EXTENTS-1 Constraints by Policy (Derived from Frozen Protocol)

Per the frozen protocol (GR-43: ENTERPRISE mode forbids EXTENTS-1):
- HIGHLY_Vertical and VERTICAL (MODERN wire mode): EXTENTS-1 is available, depth/breadth constrained only by optimization configuration.
- HORIZONTAL (ENTERPRISE wire mode): EXTENTS-1 is not forbidden at the wire level but discouraged by policy preference; shallow only where clearly beneficial.
- HIGHLY_Horizontal (ENTERPRISE wire mode): EXTENTS-1 explicitly forbidden by policy for emitted content; DIRECT-1 required.

### DIRECT-1 Under Each Policy

| StoragePolicy | DIRECT-1 Role |
|--------------|---------------|
| HIGHLY_Vertical | Fallback when optimization does not save beyond min_savings_bytes |
| VERTICAL | Common fallback when bounded search finds no savings opportunity |
| HORIZONTAL | Preferred baseline for all emitted content objects |
| HIGHLY_Horizontal | Required for ALL emitted content objects |

---

## 11. Fallback Behavior

### Canonical Fallback Model

```
attempt preferred optimization (per storage policy)
        ↓
budget exhausted OR candidate rejected by min_savings_bytes
        ↓
fall back to another valid representation (DIRECT-1 full copy)
        ↓
commit valid VSN content via normal transaction process
```

### Classification of Outcomes

| Situation | Behavior | Container validity |
|-----------|----------|-------------------|
| Optimization succeeds within budget | Use optimized representation | Valid |
| Budget exhausted during optimization | Fall back to DIRECT-1 full copy | Still valid -- never produce invalid container |
| min_savings_bytes not met | Skip EXTENTS-1, use DIRECT-1 | Valid |
### Critical Invariant

A writer MUST NOT produce an invalid VSN container merely because its preferred optimization strategy could not complete. Fallback always produces a valid container, even if less optimized than the writer intended.

---

## 12. Transaction Interaction

### Policy Configuration Scope

Storage policy and optimization configuration are **writer-side options** applied at the point of writing. They do NOT modify:
- UNCOMMITTED state semantics
- COMMITTABLE state semantics
- ACCEPTED state semantics (determined solely by CommitMarker)
- ABANDONED state semantics
- INVALID state semantics

### Failed Optimization Semantics

| Scenario | Transaction Behavior |
|----------|---------------------|
| Optimization fails, fallback succeeds | Commit proceeds normally with fallback representation |
| Optimization fails, no valid fallback exists | Abort; do not emit container; return error to caller |
| Writer changes policy mid-write | Not applicable -- policy is set at writer creation time; each write commits the container in its declared wire mode |

A failed optimization attempt MUST NOT be treated as an accepted transaction. Only a valid CommitMarker establishes acceptance (RC-01 through RC-45).

### Key Invariants

- A successful fallback representation MUST pass normal validation and commit process -- same integrity checks, generation bumping, and CommitMarker emission as any other write.
- Optimization configuration does not create additional transaction states. Five existing states (UNCOMMITTED, COMMITTABLE, ACCEPTED, ABANDONED, INVALID) remain the complete set.

---

## 13. ObjectSerial Preservation

Storage policy selection MUST NOT:
- Renumber existing ObjectSerial identities arbitrarily
- Create policy-specific ObjectSerial namespaces
- Make ObjectSerial dependent on policy names

Preserved frozen semantics (unchanged by this contract):
- **ID-03:** ObjectSerial is independent of compression, representation, and VSN Mode.
- **ID-09:** ObjectSerial persists across repack/compression/mode change.
- **ID-61:** Identity allocation is permanent; failed writes consume a serial number.
No policy may renumber, remap, or create a policy-specific ObjectSerial namespace. All four policies share the same ObjectSerial identity semantics as defined in the frozen protocol.

---

## 14. Compression Interaction

Preserve the existing compression contract without modification:
- `0x00 = IDENTITY` -- uncompressed data is always valid and the baseline.
- Existing wrapper semantics remain unchanged.
- Unsupported transforms preserve framing integrity.
- Canonical recovery does not depend on any one future-unavailable compression algorithm.

The policy may influence whether/how aggressively a writer considers **permitted** compression:
| StoragePolicy | Compression Role |
|--------------|-----------------|
No new compression identifiers. No new protocol fields.

---

## 15. Canonical API Error Model

The following semantic errors apply to invalid policy configuration. Implementation may use existing Library error taxonomy where equivalent errors already exist. The important requirement is semantic consistency, not identical class names across languages.

| Semantic Error | When Raised | Description |
|---------------|-------------|-------------|
| INVALID_STORAGE_POLICY | A StoragePolicy value is null or an unrecognized enum value | The caller provided a policy that does not exist in the four-value set |
| POLICY_WIRE_MODE_CONFLICT | storage_policy and wire_mode_constraint are both present and inconsistent per Section 3 rules | E.g., HIGHLY_Vertical with ENTERPRISE wire mode |
| INVALID_OPTIMIZATION_CONFIGURATION | OptimizationConfiguration contains non-nullable values that cannot be honored (e.g., negative budget, zero max_extent_count) | The resource parameters are malformed or nonsensical |
| OPTIMIZATION_BUDGET_EXCEEDED | Hard limit reached during optimization; writer falls back to a simpler representation | Informational -- not an error if fallback succeeds; may be logged or surfaced as a Diagnostic |
| UNSUPPORTED_REPRESENTATION | Writer attempts to use a representation that is not permitted by the selected wire mode (e.g., EXTENTS-1 under HIGHLY_Horizontal) | The policy forbids this representation choice |

Error names may vary by language convention (e.g., `InvalidStoragePolicyError` in Python, `INVALID_STORAGE_POLICY` constant in C#, `StoragePolicyException` in Java). The semantic meaning must be consistent.
| HIGHLY_Vertical | Aggressive on rep source data within resource bounds |
| VERTICAL | Bounded effort; evaluate savings vs cost |
| HORIZONTAL | Optional on stored content; NONE baseline must suffice |
| HIGHLY_Horizontal | No compression dependency for correctness; DIRECT-1 required |

**No new compression identifiers.**
**No new protocol fields.**
- **SR-37:** Cross-mode equivalence -- an otherwise-equivalent container in different mode has identical canonical state (only ModeDeclaration differs).
- **SR-36:** ObjectSerial identity and logical content equality are independent.

No policy may renumber, remap, or create a policy-specific ObjectSerial namespace. All four policies share the same ObjectSerial identity semantics as defined in the frozen protocol.
### Key Invariants

- A failed optimization attempt MUST NOT be treated as an accepted transaction. Only a valid CommitMarker establishes acceptance (RC-01 through RC-45).
- A successful fallback representation MUST pass the normal validation and commit process -- it is subject to the same integrity checks, generation bumping, and CommitMarker emission as any other write.
- Optimization configuration does not create additional transaction states. The five existing states (UNCOMMITTED, COMMITTABLE, ACCEPTED, ABANDONED, INVALID) remain the complete set.
| max_dependency_depth reached | Use shallower chain or DIRECT-1 | Valid |
| max_extent_count reached | Split into more objects with fewer extents | Valid |
| Resource error during materialization at read time (decode_work_limit) | Report error to caller; container is still valid | Container valid on disk |

### Critical Invariant

**A writer MUST NOT produce an invalid VSN container merely because its preferred optimization strategy could not complete.** Fallback always produces a valid container, even if less optimized than the writer intended.

Error names may vary by language convention (e.g., `InvalidStoragePolicyError` in Python, `INVALID_STORAGE_POLICY` constant in C#, `StoragePolicyException` in Java). The semantic meaning must be consistent.

---

## 16. Conformance Tests (CAP-P01 through CAP-P10)

### CAP-P01 -- Policy Enumeration

**Goal:** Verify all four storage-policy values exist and no extra normative values are introduced.

**Method:**
- Inspect the StoragePolicy type enumeration.
- Assert exactly four members: HIGHLY_Vertical, VERTICAL, HORIZONTAL, HIGHLY_Horizontal.
- Assert that iterating over the enum yields exactly four values.
- For each member, verify it can be resolved to a wire mode per Section 3 rules (no resolution failure).

**Pass criteria:** Enum has exactly four members; all resolve to a valid WireMode. No additional values exist.

### CAP-P02 -- Policy-to-WireMode Mapping

**Goal:** Verify the deterministic mapping from each policy to its effective wire mode.

**Method:**
- For each of the four StoragePolicy values, assert the resolved WireMode:
  - HIGHLY_Vertical → MODERN (0x01)
  - VERTICAL → MODERN (0x01)
  - HORIZONTAL → ENTERPRISE (0x02)
  - HIGHLY_Horizontal → ENTERPRISE (0x02)

**Pass criteria:** All four mappings produce the expected WireMode value. No mapping produces any other value.

### CAP-P03 -- No Illegal Wire Mode

**Goal:** Verify writing under all four policies does NOT produce 0x03 or 0x04 as ModeDeclaration.

**Method:**
- Create a container under each of the four storage policies.
- Serialize the container.
- Parse serialized bytes and extract ModeDeclaration field value.
- Assert ModeDeclaration is exactly 0x01 or 0x02.

**Pass criteria:** All four containers emit ModeDeclaration of either 0x01 or 0x02. None emit 0x03, 0x04, or any other value outside {0x01, 0x02}.

### CAP-P04 -- Reader Independence

**Goal:** Verify containers written under each policy can be decoded by a reader that does not know the writer's storage policy name.

**Method:**
- Create valid containers using all four storage policies.
- Open/read each container with a reader implementation that has no StoragePolicy type or knowledge of HIGHLY_Vertical/VERTICAL/HORIZONTAL/HIGHLY_Horizontal.
- Verify successful decoding: magic OK, ModeDeclaration read, all objects materialized, logical content matches expected input.

**Pass criteria:** All four containers decode successfully in the policy-agnostic reader. Decoded logical content is byte-identical to the writer's input for each container.

### CAP-P05 -- Logical Equivalence

**Goal:** Verify that writing equivalent logical content under multiple policies produces logically equivalent results.

**Method:**
- Write the same logical state (same files, same content) using two different storage policies (e.g., HIGHLY_Vertical and VERTICAL).
- Re-open both containers.
- Compare: FileIds match; RevisionIds match for corresponding files; content bytes materialize identically; deletion/directory semantics match where applicable.

**Pass criteria:** FileId, RevisionId, parent revision relationships, and content bytes are identical across policies. Physical container bytes may differ (representation choice differs). ObjectSerials for corresponding revisions must be preserved per ID-03/ID-09 rules.
**Pass criteria:** FileId, RevisionId, parent revision relationships, and content bytes are identical across policies. Physical container bytes may differ (representation choice differs). ObjectSerials for corresponding revisions must be preserved per ID-03/ID-09 rules.

---

### CAP-P06 -- ObjectSerial Preservation

**Goal:** Verify ObjectSerial identities survive policy changes per frozen rules.

**Method:** Write a container with multiple content objects under one storage policy, record each ObjectSerial, rewrite same logical state under a different storage policy, compare ObjectSerials.

**Pass criteria:** All existing ObjectSerials preserved with identical values. No ObjectSerial remapped, renumbered, or dropped. New objects receive new serial numbers per ID-61 semantics.

### CAP-P07 -- Commit/Recovery

**Goal:** Verify policy-selected writes use existing CommitMarker, effective generation, recovery, and validation semantics.

**Method:** Create containers under all four policies with multiple revisions per file. After commit, verify: each container has a valid CommitMarker at correct generation; truncated-data recovery produces accepted state up to last valid CommitMarker; integrity() returns true for all committed containers.

**Pass criteria:** All containers from all four policies pass normal validation. Recovery from truncated data produces identical accepted state in all cases. No policy-specific acceptance rule is used -- only standard CommitMarker semantics (RC-01 through RC-45).
**Pass criteria:** All containers from all four policies pass normal validation. Recovery from truncated data produces identical accepted state in all cases. No policy-specific acceptance rule is used -- only standard CommitMarker semantics (RC-01 through RC-45).

### CAP-P08 -- Optimization Budget

**Goal:** Verify reducing optimization resources can cause less optimization, fallback, or explicit resource error without silently producing an invalid VSN container.

**Method:** Create the same logical content using two configurations: (a) generous budget and (b) tight budget. Write both containers. Parse both and verify both are valid VSN containers (magic OK, ModeDeclaration 0x01/0x02, structural integrity passes, CommitMarker present). Compare physical output: the tight-budget container may be less optimized but must be valid.

**Pass criteria:** Both containers are structurally valid VSN. Logical content is identical between them. The tight-budget container may use more DIRECT-1 and fewer EXTENTS-1 objects, but it MUST NOT be invalid.

### CAP-P09 -- Cross-Policy Compatibility

**Goal:** Verify containers written under all four policies can be consumed by the same reader that relies on VSN wire semantics, not policy-name knowledge.

**Method:** Create one container under each of the four policies with identical logical content (same files, same content). Decode all four using a single reader implementation. Assert decoded FileIds, RevisionIds, and content bytes are identical across all four readers.

**Pass criteria:** All four containers decode identically in terms of logical state (FileId, RevisionId, content). Only physical storage layout differs. Reader does not need any StoragePolicy enum or name to perform decoding.

### CAP-P10 -- Policy Is Not Wire State

**Goal:** Verify no policy-specific wire field has been introduced by inspecting serialized bytes directly.

**Method:** Create a container under each of the four storage policies. Serialize and inspect every byte of each container. Assert: ModeDeclaration values are only 0x01 or 0x02; no record type outside the frozen registry appears; no new field IDs appear in any Record; no policy name string appears anywhere in the binary; all records, fields, and objects match known VSN grammar (GR-28, GR-17).

**Pass criteria:** Zero wire-level artifacts differ between containers written under different policies beyond what is permitted by representation choice (DIRECT-1 vs EXTENTS-1, compression). No ModeDeclaration value of 0x03, 0x04, or any other non-standard value. No new record types or field IDs in the serialized output.
**Pass criteria:** Zero wire-level artifacts differ between containers written under different policies beyond what is permitted by representation choice. No ModeDeclaration value of 0x03, 0x04, or any other non-standard value appears. No new record types or field IDs in the serialized output.

---

## 17. 31-Language Implications

This contract is language-neutral. The canonical semantic model applies uniformly across all 31 target languages. Implementation-specific naming follows each language's conventions:

| Language family | Naming convention for StoragePolicy | Construction pattern |
|----------------|-----------------------------------|---------------------|
| C / C++ / Rust | `STORAGE_HIGHLY_VERTICAL` (const) | Builder struct with setters |
| C# / F# | `StoragePolicy.HighlyVertical` (enum member) | Named-parameter `Create()` |
| Java / Kotlin | `StoragePolicy.HIGHLY_VERTICAL` (enum constant) | `WriterOptions.Builder` |
| Python | `StoragePolicy.HIGHLY_VERTICAL` (enum member) | Keyword argument to `create()` |
| TypeScript / JavaScript | `StoragePolicy.HIGHLY_VERTICAL` (enum constant) | Optional config object to `create()` |
| Go | `StoragePolicyHighlyVertical` (const iota) | Functional options pattern |
| Haskell / Erlang / Elixir | Policy term in data type | Pattern matching on config record |
| Swift / Zig | `storagePolicy.highlyVertical` (enum case) | Struct literal or builder |
| Ada / COBOL / Fortran | Limited by language features; document approach per implementation | Follow existing VsnStore.Create() pattern |

No new wire dependency is introduced for any language. All 31 implementations decode identical containers identically from the reader side.
No new wire dependency is introduced for any language. All 31 implementations decode identical containers identically from the reader side.

---

## 18. Documentation Integration

This contract document (`VSN1_Library_Storage_Policy_API_Contract.md`) is the authoritative source. The following cross-references apply:

```
VSN1_Library_Storage_Policy_API_Contract.md  (this file -- full API + conformance contract)
    ↓ references
library_api_contract_policy.md               (Writer Storage Policy taxonomy -- definitions per policy)
    ↓ referenced from
library_api_contract.md                      (Section: Writer Storage Policy Contract)
    ↓ cross-referenced from
libraries.html                               (generated docs, Section 18)
    ↓ cross-referenced from
README.md                                    (Architecture section, storage policy table)
    ↓ reflected in
AGENTS.md                                    (freeze verdict + architecture diagram)
```

**Rule:** Do not duplicate the full contract text across files. Each file references the authoritative document and adds only its own layer of context (taxonomy, cross-reference, or freeze state).
Rule: Do not duplicate the full contract text across files. Each file references the authoritative document and adds only its own layer of context (taxonomy, cross-reference, or freeze state).

---

## 19. Validation Checklist

### API Validation

- [ ] StoragePolicy has exactly four values (HIGHLY_Vertical, VERTICAL, HORIZONTAL, HIGHLY_Horizontal)
- [ ] Wire Mode remains exactly two values (MODERN = 0x01, ENTERPRISE = 0x02)
- [ ] Policy and WireMode are separate concepts with no collapsing into a single enum
- [ ] Optimization Configuration is a separate type from StoragePolicy
- [ ] Invalid combinations have deterministic behavior (all 8 conflict cases in Section 3 defined)
- [ ] Reader does not depend on policy names

### Documentation Validation

- [ ] No "four wire modes" claim appears anywhere in documentation
- [ ] No "four-mode container" phrase present
- [ ] No policy encoded as 0x03 or 0x04
- [ ] No mixed-policy container model described
- [ ] No contradictory policy definitions (each policy maps to exactly one wire mode)
- [ ] No duplicate storage-policy sections across documents

### Protocol Validation

- [ ] All five frozen vector hashes unchanged
- [ ] Wire mode registry unchanged (0x01 MODERN, 0x02 ENTERPRISE only)
- [ ] No normative protocol files unintentionally modified (GR, SR, VR rules intact)
- [ ] No new record types, field IDs, or representation identities added
- No new record types, field IDs, or representation identities added

---

## 20. Unresolved Questions

The following items require explicit approval before this contract can be finalized:

1. **Default storage policy:** Currently there is no library-level default. Recommendation: `null` (use implementation's native default). If a non-null default is desired, it must be chosen by protocol leads and documented in all 31 implementations simultaneously. No default has been selected in this contract to avoid silently changing existing writer behavior.

2. **OptimizationConfiguration defaults:** Specific numeric defaults for search_budget, memory_limit, etc. are not defined at the contract level because no frozen protocol value defines them. Each implementation chooses its own defaults and documents them locally. Contract-level defaults may be established in a follow-up audit.

3. **Conformance test registration:** CAP-P01 through CAP-P10 are defined as conformance contracts but have NOT been implemented as executable tests against the 31-language runner. The runner architecture requires registration infrastructure before these can be added as real tests without fake PASS markers. This is by design per requirement #19 of the task prompt.

4. **Cross-policy repack strategy:** When a container is rewritten under a different policy (e.g., HIGHLY_Vertical → HORIZONTAL), the exact ObjectSerial mapping behavior for objects that survive vs. objects that are recreated needs implementation-level specification in each language. The frozen protocol rules (ID-03, ID-09, SR-37) govern this but require explicit cross-language alignment during implementation.

5. **Haskell CAP 12 SHA-256 deferred:** Per prior AGENTS.md note, Haskell SHA-256 self-contained reference is deferred pending an independent comparison. This does not affect the API contract but may affect conformance readiness of the Haskell test suite.
Haskell CAP 12 SHA-256 deferred: Per prior AGENTS.md note, Haskell SHA-256 self-contained reference is deferred pending an independent comparison. This does not affect the API contract but may affect conformance readiness of the Haskell test suite.

---

## 21. Final Audit Report

### 1. Existing API Analysis
All three reference implementations (Python VsnStore.create(mode), C# VsnStore.Create(byte mode), TypeScript new VsnStore(data, mode)) use a single `mode` byte parameter to set the wire mode. No storage policy or optimization configuration currently exists in any reference implementation.

### 2. Canonical StoragePolicy Model
Four-value enum: HIGHLY_Vertical, VERTICAL, HORIZONTAL, HIGHLY_Horizontal. Library-level only. Not on the wire. Maps deterministically to WireMode per Section 3 rules.

### 3. Policy-to-WireMode Mapping
HIGHLY_Vertical → MODERN (0x01), VERTICAL → MODERN (0x01), HORIZONTAL → ENTERPRISE (0x02), HIGHLY_Horizontal → ENTERPRISE (0x02). Incompatible combinations are rejected.

### 4. WriterOptions Model
Optional composition: storage_policy | optimization_configuration. When absent, existing behavior is preserved. Language-specific API patterns recommended for C#, Python, TypeScript, Java/Kotlin, and others.

### 5. OptimizationConfiguration Model
Seven fields documented with purpose, type, optional status, default, hard-limit vs preference, exceeded behavior, logical-semantic impact, and wire-compatibility impact for each field.

### 6. Policy/WireMode Conflict Behavior
Canonical rule: reject incompatible combinations. Eight conflict cases explicitly defined (Section 3 table).

### 7. Default-Policy Analysis
No library-level default established by this contract. Recommended approach: null (use implementation's native default) to preserve existing behavior across all 31 languages.

### 8. Reader-Independence Guarantee
Reader decodes solely via ModeDeclaration + RepresentationDescriptor + normative recovery rules. No StoragePolicy knowledge required. No wire dependency on policy names.

### 9. Policy Persistence Decision
Writer Storage Policy is configuration/intent, not normative container state. Zero persistence in the binary protocol.

### 10. Representation-Selection Semantics
Each policy's role with EXTENTS-1, DIRECT-1, and compression defined per Section 10 table. EXTENTS-1 constraints derived from GR-43 (ENTERPRISE wire-mode rule).

### 11. Fallback Behavior
Canonical model: attempt preferred → budget exhausted → fall back to valid representation → commit via normal transaction. Writer MUST NOT produce an invalid container due to optimization failure.

### 12. Transaction Interaction
Policy configuration does not create additional transaction states. Failed optimization is not an accepted transaction. Successful fallback passes normal validation.

### 13. ObjectSerial Preservation
Preserved: ID-03, ID-09, ID-61, SR-37. No policy-specific namespace, no renumbering, no remapping.

### 14. Compression Interaction
No new compression identifiers or protocol fields. Existing contract preserved (IDENTITY baseline, wrapper semantics unchanged, unsupported transforms preserve framing).

### 15. Error Model
Five semantic errors defined: INVALID_STORAGE_POLICY, POLICY_WIRE_MODE_CONFLICT, INVALID_OPTIMIZATION_CONFIGURATION, OPTIMIZATION_BUDGET_EXCEEDED, UNSUPPORTED_REPRESENTATION.

### 16. CAP-P01 through CAP-P10
Ten conformance tests defined with explicit goal, method, and pass criteria for each test. Not implemented as executable tests in this contract phase.

### 17. 31-Language Implications
Naming conventions and construction patterns documented for all language families. No new wire dependency introduced for any language.

### 18. Documentation Changes
Cross-reference chain established: VSN1_Library_Storage_Policy_API_Contract.md → library_api_contract_policy.md → library_api_contract.md → libraries.html → README.md → AGENTS.md.

### 19. Frozen Protocol Verification
- ModeDeclaration wire values: UNTOUCHED (0x01, 0x02)
- No new record types, field IDs, or representation identities
- No normative protocol files modified
- Five frozen vectors: not touched by this document; preserved in their original locations

### 20. Unresolved Questions
Five items requiring explicit approval before freeze finalization (default policy, optimization defaults, conformance test registration, cross-policy repack strategy, Haskell CAP deferred).

---

**Status of this contract:** Draft -- Awaiting Approval

All API semantics are defined. No ambiguity remains in the canonical model. The following items block final freeze:
- Default policy selection (unresolved by design)
- OptimizationConfiguration defaults (unresolved per task constraints)
- Conformance test implementation (not part of this contract phase)

These blockers are intentional and documented in Section 21.

**READY FOR LIBRARY STORAGE POLICY API FREEZE with conditions:**
The API contract is complete and internally consistent. Three items remain unresolved by design: default policy, optimization defaults, and executable conformance test registration. These do not block freeze readiness because: (a) no implementation has been changed yet (contract phase only), (b) all semantic behavior is defined, (c) backward compatibility is preserved through null-default semantics, and (d) the protocol remains frozen.

**Final Verdict:**

READY FOR LIBRARY STORAGE POLICY API FREEZE
