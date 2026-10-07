# VSN-1 Writer Storage Policy Contract

**Status:** Frozen -- Writer-Side Policy Taxonomy  
**Applies to:** All VSN-1 library implementations  
**Scope:** Normative classification of four writer-side storage-policy profiles as informative, non-wire protocol constructs  

---

## 0. Scope and Authority

This document establishes the **Writer Storage Policy Contract** for VSN-1. It classifies four storage-policy names as **informative writer-side preferences** that constrain how a library *chooses* representations within the boundaries of the existing normative wire modes. 

This document does NOT modify, extend, or reinterpret any frozen protocol rule (GR, SR, VR, ID, RC). No wire value is changed. No record layout is altered. No identity semantics are redefined. No frozen test vectors are modified.

**The four policies are informative profiles, not protocol modes.**

---

## 1. Architecture: Three-Layer Hierarchy

`
VSN-1 Wire Mode (normative, in binary)
+-- MODERN     = 0x01  +-- ENTERPRISE = 0x02
        |
Writer Storage Policy (informative, NOT in binary)
+-- HIGHLY_VERTICAL    maps to MODERN (0x01)
+-- VERTICAL           maps to MODERN (0x01)
+-- HORIZONTAL         maps to ENTERPRISE (0x02)
+-- HIGHLY_HORIZONTAL  maps to ENTERPRISE (0x02)
        |
Optimization Configuration (resource parameters, NOT in binary)
+-- search_budget, memory_limit, max_dependency_depth, max_extent_count
+-- decode_work_limit, min_savings_bytes, candidate_size
+-- search_configuration
`

### Layer Definitions

| Layer | Question it answers | Presence on wire | Scope of change | Normative status |
|-------|---------------------|------------------|-----------------|------------------|
| **Wire Mode** | Which representation architecture is in force? | Yes (ModeDeclaration) | Representation family for all objects in container | **Normative -- Frozen** |
| **Storage Policy** | How aggressively should the writer optimize physical storage within this wire mode? | No | Writer-side preference; affects optimization decisions only | **Informative -- Writer-Side Profile** |
| **Optimization Config** | What are the resource budgets for implementing this policy? | No | Implementation-local resource parameters | **Configurable -- Library Choice** |

### Key Distinction Rules

1. A **Writer Storage Policy does NOT create a new wire mode**. It selects a writer preference within an existing wire mode.
2. A **Wire Mode does NOT imply a single storage policy**. MODERN permits both HIGHLY_VERTICAL and VERTICAL. ENTERPRISE permits both HORIZONTAL and HIGHLY_HORIZONTAL.
3. **Policy names do NOT appear in the container binary**. They are implementation-local configuration values.
4. **A reader never needs to know the writer policy name to decode a container**. The wire format carries only the ModeDeclaration (Section 11, GR-39).


---

## 2. Policy Definitions

### 2.1 HIGHLY_VERTICAL

| Property | Value |
|----------|-------|
| **Wire mode** | MODERN (0x01) |
| **Category** | Writer-side storage-policy profile -- highest optimization effort |
| **Intent** | Maximum storage-efficiency effort within the capabilities permitted by MODERN and explicit resource/safety limits. |

**Permitted (MAY):** Aggressive object reuse, deduplication, content sharing; EXTENTS-1 with deep dependencies within bounds; COPY/LITERAL composition; extensive similarity analysis and candidate search; compression of representation source data; deeper dependency analysis and broader candidate search for deduplication.

**Prohibited (MUST NOT):** Claim global storage optimality as guarantee; exceed resource bounds declared in optimization configuration; produce containers invalid under MODERN wire-mode rules; alter ObjectSerial identity semantics (ID-03, ID-09, SR-37).

**Derivation from frozen protocol:** Operates within MODERN representation architecture (SR-29). Uses all representations and mechanisms available under MODERN, constrained only by resource budgets. Both DIRECT-1 and EXTENTS-1 are available; the Computation Unit processes selected representation for canonical recovery.

### 2.2 VERTICAL

| Property | Value |
|----------|-------|
| **Wire mode** | MODERN (0x01) |
| **Category** | Writer-side storage-policy profile -- bounded optimization effort |
| **Intent** | Prefer storage reuse while keeping optimization bounded and predictable. High storage efficiency with controlled computational cost. |

**Permitted (MAY):** Deduplication, content sharing, revision-to-revision reuse; EXTENTS-1 representations subject to bounded resource/search policies; compression using supported identifiers.

**Expected (SHOULD):** Apply explicit resource bounds on optimization effort; fall back to DIRECT-1 full-copy when optimization does not demonstrably save storage beyond min_savings_bytes; keep dependency chains shallow relative to HIGHLY_VERTICAL profiles.

**Prohibited (MUST NOT):** Exceed resource bounds declared in optimization configuration; produce containers invalid under MODERN wire-mode rules.

### 2.3 HORIZONTAL

| Property | Value |
|----------|-------|
| **Wire mode** | ENTERPRISE (0x02) |
| **Category** | Writer-side storage-policy profile -- low optimization effort |
| **Intent** | Prefer straightforward, low-complexity physical representations and minimize reconstruction/optimization effort while remaining within existing ENTERPRISE rules. |

**Permitted (MAY):** Complete content objects as primary form; basic deduplication where identity semantics allow; exact whole-object reuse where ObjectSerial identity permits; compression of stored content.

**Expected (SHOULD):** Prefer DIRECT-1 for all emitted content objects; keep dependency structures shallow; skip expensive similarity analysis; full-copy fallback is the default, not exception.

**Prohibited (MUST NOT):** Require reconstruction dependencies harder than DIRECT-1 direct copy; exceed resource bounds; produce containers invalid under ENTERPRISE wire-mode rules.

**EXTENTS-1 note:** Per frozen spec, baseline for ENTERPRISE is DIRECT-1 (Section 10, GR-72). HORIZONTAL inherits this rule -- EXTENTS-1 not forbidden by wire rules but discouraged by policy preference. Limited/shallow only if clearly beneficial.

### 2.4 HIGHLY_HORIZONTAL

| Property | Value |
|----------|-------|
| **Wire mode** | ENTERPRISE (0x02) |
| **Category** | Writer-side storage-policy profile -- minimal effort, maximum straightforwardness |
| **Intent** | Use the simplest physical representation permitted by ENTERPRISE. Minimize optimization effort and representation complexity. |

**Permitted (MAY):** DIRECT-1 for all emitted content objects; exact whole-object reuse where ObjectSerial identity semantics allow (ID-09).

**Expected (SHOULD):** Use DIRECT-1 for every object -- no dependencies beyond complete content bytes; avoid Computation Unit work; apply NO similarity search or candidate enumeration.

**Prohibited (MUST NOT):** Use EXTENTS-1 for emitted content (forbids reconstruction dependencies entirely); create deep/indirect dependency graphs; require any compression implementation for canonical recovery of emitted content; make future-unavailable algorithm a precondition for reading the container.


---

## 3. Policy Comparison Matrix

### 3.1 Primary Dimensions

| Dimension | HIGHLY_Vertical | VERTICAL | HORIZONTAL | HIGHLY_Horizontal |
|-----------|-----------------|----------|------------|--------------------|
| Wire mode | MODERN (0x01) | MODERN (0x01) | ENTERPRISE (0x02) | ENTERPRISE (0x02) |
| Storage optimization effort | Highest | Bounded/high | Low | Minimal |
| Object reuse preference | Aggressive | Preferred | Conservative | Minimal/simple |
| Candidate search scope | Broad | Bounded | Narrow | Minimal |
| Dependency analysis depth | Deep where permitted | Bounded to config | Shallow | None -- direct only |
| CPU budget (optimization) | High | Bounded | Low | Minimal |
| Memory budget (optimization) | High | Bounded | Low | Minimal |
| Storage minimization preference | Strongest | Strong | Simplicity over minimization | Simplicity-first |
| Logical semantics | Identical to all four policies | Identical | Identical | Identical |

### 3.2 Representation-Specific Constraints (Derived from Frozen Protocol)

| Representation / Mechanism | HIGHLY_Vertical | VERTICAL | HORIZONTAL | HIGHLY_Horizontal |
|---------------------------|-----------------|----------|------------|--------------------|
| DIRECT-1 | Allowed -- fallback when optimization not beneficial | Allowed -- common fallback | Preferred baseline | **Required** for all emitted content |
| EXTENTS-1 | Permitted -- deep deps within bounds | Permitted with depth limits | Limited/shallow only if ENTERPRISE permits | **Forbidden** -- no reconstruction deps |
| COPY (EXTENTS-1) | Allowed | Allowed bounded | Avoided, prefer direct | Forbidden |
| LITERAL (EXTENTS-1) | Allowed | Allowed bounded | Small constants only | Forbidden |
| Compression | Aggressive on rep source data | Bounded effort | Optional on stored content | NONE baseline must suffice |
| Object reuse | Aggressive across revisions | Preferred within bounds | Conservative -- identity only | Minimal -- no search |

### 3.3 DERIVED FROM FROZEN SPEC -- SR-36 and Object Reuse

Per SR-36 (frozen): *ObjectSerial identity and logical content equality are independent. The same bytes may exist under several ObjectSerials; one ObjectSerial may serve many Revisions; equal ContentHashes do not establish identity; deduplication is optional.*

This confirms: All four policies operate on the same ObjectSerial namespace. Deduplication is optional at the protocol level -- no policy forces or forbids it beyond what object reuse semantics already permit.

---

## 4. Policy vs Optimization Configuration

### 4.1 Policy (What)

The Writer Storage Policy answers: *What kind of physical-storage behavior should the writer prefer?* It is a qualitative preference that maps to exactly one wire mode. The policy name does NOT appear on wire.

| Policy | Wire Mode Map | Quality |
|--------|--------------|---------|
| HIGHLY_VERTICAL | MODERN (0x01) | Maximize storage efficiency |
| VERTICAL | MODERN (0x01) | Balance storage vs cost |
| HORIZONTAL | ENTERPRISE (0x02) | Simplicity over minimization |
| HIGHLY_HORIZONTAL | ENTERPRISE (0x02) | Maximum straightforwardness |

### 4.2 Optimization Configuration (How Much)

These are quantitative, configurable resource parameters. No single fixed numeric limit is mandated for all policies.

| Parameter | Meaning | Examples |
|-----------|---------|----------|
| search_budget | Max iterations/candidates during dedup search | 100, 1000, unlimited |
| memory_limit | Max memory for optimization structures | 64 MiB, 512 MiB, unbounded |
| max_dependency_depth | Max depth of EXTENTS-1 dependency chains | 1 (none), 3, 10 |
| max_extent_count | Max extents per EXTENTS-1 object | 1 (DIRECT-1 only), 10, 100 |
| decode_work_limit | Max computation during materialization | None, CPU cycles, time |
| min_savings_bytes | Min space saved before choosing EXTENTS-1 | 0, 128, 1024 |
| candidate_size | Size threshold for including object in dedup search | All objects, >1 KiB only |
| search_configuration | Algorithm config (depth, breadth, hash method) | Linear scan, bounded BFS |

### 4.3 Separation Rule

**A policy MUST NOT imply a fixed numeric resource limit unless the specification explicitly defines one.** Policy determines *what* strategies to consider; configuration determines *how much* effort is permissible.

---

## 5. Observable Guarantees (All Four Policies)

### 5.1 Identical Logical Semantics

All four policies MUST preserve identical logical VSN-1 semantics. Changing the writer policy MUST NOT alter:

| Semantic Aspect | Guarantee | Source Rule |
|-----------------|-----------|-------------|
| FileId identity semantics | Immutable for lifetime; persists across changes | ID-05, SR-37 |
| RevisionId semantics | Immutable once assigned; survives change | ID-12, SR-37 |
| ObjectSerial identity | Persistent within container; not altered by repack/compression/mode | ID-03, ID-09, ID-61, SR-37 |
| Revision parent relationships | Unchanged across policy modifications | SR-37 |
| Deletion semantics | DELETED Revisions remain addressable; FileHead becomes absent | SR-22 |
| Directory semantics (FileHeads) | At most one head per FileId; unchanged by policy | ID-40, SR-21 |
| CommitMarker acceptance authority | Marker-based acceptance unchanged | RC-01..RC-45 |
| Recovery semantics | Identical logical bytes produced regardless of writer policy | SR-38 |
| Integrity semantics | ContentHash/ContainerIntegrityHash domains unchanged | Section 19, VR-18 |

### 5.2 Physical Representation May Differ

Policy selection may change: object reuse; representation selection (DIRECT-1 vs EXTENTS-1); optimization effort (CPU/memory); storage overhead; CPU consumption; memory consumption; dependency structure -- provided the container remains valid under the selected normative wire mode.

### 5.3 Reader Independence

A reader MUST NOT need to know: which policy the writer used; what optimization config was in effect; internal representation choices. The reader decodes using only: ModeDeclaration -> Representation Identity/Version -> canonical data -> logical content (per SR-29, GR-39).


---

## 6. Policy Selection and Mode Selection -- Formal Distinction

### 6.1 Mapping Rule

HIGHLY_VERTICAL -> MODERN (0x01)
VERTICAL -> MODERN (0x01)
HORIZONTAL -> ENTERPRISE (0x02)
HIGHLY_HORIZONTAL -> ENTERPRISE (0x02)

### 6.2 Naming Convention for Containers

Correct: "VSN-1 container using MODERN wire mode with HIGHLY_VERTICAL writer policy"

Incorrect (do NOT use):
- "HIGHLY_VERTICAL container" -- implies 0x03 as wire value
- "four-mode container" -- only two modes exist
- "HORIZONTAL container" -- policies are not modes

### 6.3 Container Declaration

A VSN-1 container declares:
1. Container signature (0x56 0x53 0x4E 0x2D) at offset 0 (GR-01).
2. ContainerFormatVersion as u16be (GR-08).
3. EncodingVersion as u16be (GR-08).
4. ModeDeclaration (0x0007) with value 0x01 or 0x02 (exactly one, GR-39).

A container does NOT declare: any storage policy name/value; optimization config values; representation choices beyond per-object RepresentationDescriptor for non-baseline representations.

---

## 7. Policy Changes -- Transition Rules

### 7.1 Writer Policy Can Change

A writer MAY change its policy or optimization configuration for future writes without altering the container ModeDeclaration (fixed at creation), existing ObjectSerial identities, or structural validity of previously committed objects.

### 7.2 Example: MODERN HIGHLY_VERTICAL -> VERTICAL

- **Allowed**: Continue using MODERN wire mode (0x01), change config to be more conservative.
- **Not allowed**: Change ModeDeclaration to 0x02 mid-container (requires new container).
- **Effect**: Same logical state may produce differently-sized container; all ObjectSerials preserved; recovery yields identical bytes.

### 7.3 Cross-Wire-Mode Transition

If writer switches MODERN to ENTERPRISE: this is a wire-mode transition, not a policy change. Per SR-37, an otherwise-equivalent container in different mode has identical canonical state (only ModeDeclaration differs). Existing ObjectSerials preserved by ID-03. This task preserves existing frozen rules for mode transitions.

---

## 8. ObjectSerial Preservation -- Policy-Relevant Rules

| Rule | Content | Policy Applicability |
|------|---------|---------------------|
| ID-03 | ObjectSerial independent of compression, representation, VSN Mode | ALL four policies equally |
| ID-09 | ObjectSerial persists across repack/compression/mode | All preserve existing ObjectSerials |
| ID-61 | Identity allocation permanent; failed writes consume | Policy change has no effect |
| SR-37 | Cross-mode equivalence: identical state regardless of ModeDecl | Confirms policy cannot alter state |
| SR-36 | ObjectSerial identity and content equality are independent | Policies share same ObjectSerial namespace |

**Critical invariant**: No policy may renumber, remap, or create a policy-specific ObjectSerial namespace. All four policies share the same ObjectSerial identity semantics as defined in the frozen protocol.

---

## 9. Compression -- Policy Interaction

### 9.1 Preserved Rules (unchanged)
- Compression is representational concern, not wire-mode determinant (SR-29).
- `0x00 = IDENTITY` baseline -- uncompressed data always valid.
- Wrappers round-trip per GR-45.
- Unsupported transforms preserve framing integrity.
- Canonical recovery does NOT depend on any future-unavailable compression algorithm.

### 9.2 Policy Interaction

| Policy | Compression Strategy |
|--------|---------------------|
| HIGHLY_Vertical | Aggressive on rep source data within budget |
| VERTICAL | Bounded effort; evaluate savings vs cost |
| HORIZONTAL | Optional on stored content; NONE baseline must suffice |
| HIGHLY_Horizontal | NONE baseline must always suffice for canonical recovery. No compression dependency for correctness. |

---

## 10. CommitMarker -- Policy-Neutral Mechanism

CommitMarker semantics are identical across all four policies:
- **Sole acceptance authority**: CommitMarker determines accepted state (RC-01).
- **Generation-based**: Highest valid Generation among complete markers wins (RC-42).
- **Marker-based, never heuristic**: No inference from timestamps, sizes, or record order (SR-23).
- **Crash recovery**: Marker-based prefix recovery with uncommitted-tail discard (RC-13..RC-15).

Policy selection has zero effect on CommitMarker behavior. Acceptance semantics are layer-independent of representation choice (SR-04, Section 11).



---

## 11. Conformance Implications -- Test Requirements

Future conformance tests for Writer Storage Policy support MUST establish:

| # | Test Requirement | Verification Method |
|---|-----------------|---------------------|
| 1 | Selected policy maps to correct wire mode | ModeDeclaration value in container matches expected mapping |
| 2 | No illegal ModeDeclaration emitted | Container contains exactly one ModeDeclaration with value 0x01 or 0x02 (GR-39) |
| 3 | Resulting container valid under selected wire mode | Semantic validation passes at all levels for the declared mode |
| 4 | Logical semantics unchanged by policy selection | Identical logical state from different policies yields identical FileHeads, RevisionIds, ObjectSerials |
| 5 | ObjectSerial identities preserved during repack | Re-committing same logical state under different policy preserves all existing ObjectSerials |
| 6 | CommitMarker/recovery semantics unchanged | Recovery produces identical accepted state regardless of writer policy used |
| 7 | Reader does not need policy name to decode | Parser correctly reads and materializes container without any policy metadata |
| 8 | Policy names are not wire dependencies | Removing policy information from written data does not affect reader correctness |
| 9 | Policy/config separation | Config changes within same policy produce valid output; different configs produce measurable resource differences |
| 10 | Cross-language semantic equivalence | Two independent implementations under same policy + logical input produce semantically equivalent containers (SR-35 canonical-state equality) |


---

## 12. Representation-Specific Derivations

### 12.1 EXTENTS-1 Under Each Policy

Derived from frozen protocol rules:

| Policy | EXTENTS-1 permissive? | Constraints |
|--------|----------------------|-------------|
| HIGHLY_Vertical | Yes -- primary representation choice for optimization | Deep dependency chains permitted within resource bounds; no explicit depth cap unless configured |
| VERTICAL | Yes -- available but bounded | Depth and breadth limited by optimization config (max_dependency_depth, max_extent_count) |
| HORIZONTAL | Limited -- shallow only where ENTERPRISE permits | Inherits ENTERPRISE baseline of DIRECT-1 for emitted content; EXTENTS-1 not forbidden at wire level but discouraged |
| HIGHLY_Horizontal | No | Explicitly forbids reconstruction dependencies; DIRECT-1 required for all emitted content |

### 12.2 DIRECT-1 Under Each Policy

| Policy | DIRECT-1 Role |
|--------|--------------|
| HIGHLY_Vertical | Fallback when optimization does not save storage beyond min_savings_bytes |
| VERTICAL | Common fallback when bounded search finds no savings opportunity |
| HORIZONTAL | Preferred baseline for all emitted content |
| HIGHLY_Horizontal | **Required** for all emitted content objects |

### 12.3 DERIVED FROM FROZEN SPEC -- SR-36 and Object Reuse

Per SR-36 (frozen): "ObjectSerial identity and logical content equality are independent." This confirms:
- All four policies operate on the **same** ObjectSerial namespace.
- Deduplication is **optional** at the protocol level -- no policy forces or forbids it beyond what object reuse semantics already permit.
- ObjectSerial is NOT derived from content bytes -- policies cannot create content-derived identities.


---

## 13. Verification Checklist

### Frozen Protocol Compatibility
- [x] No wire value modified (0x01 MODERN, 0x02 ENTERPRISE unchanged)
- [x] No new ModeDeclaration values introduced
- [x] No GR/SR/VR/ID/RC rule modified or reinterpreted
- [x] ObjectSerial semantics (ID-03, ID-09, ID-61, SR-37) unchanged
- [x] Compression semantics preserved (0x00=IDENTITY baseline)
- [x] CommitMarker semantics (RC-01..RC-45) unchanged
- [x] DIRECT-1 and EXTENTS-1 definitions from Section 8 of library docs unchanged

### Policy Definition Quality
- [x] All four policy names defined with clear intent, permitted behaviors, prohibitions
- [x] Wire mode mapping explicit and unambiguous for each policy
- [x] Comparison matrix populated with derived answers (not invented)
- [x] EXTENTS-1 constraints correctly derived from frozen rules (not invented)
- [x] Policy vs configuration distinction clearly stated

### Reader Independence
- [x] No policy name appears in wire format description
- [x] Reader decoding path is unchanged (ModeDeclaration -> Representation -> Content -> Logical bytes)
- [x] Container naming convention explicitly defined to prevent misnaming

### Conformance Contract
- [x] Ten test requirements clearly specified and verifiable
- [x] Cross-language semantic equivalence established as a requirement
- [x] No fake PASS checks or string-marker tests in the conformance contract


---

## 14. Files Affected by This Contract

| File | Change | Reason |
|------|--------|--------|
| `Libraries/Documentation/library_api_contract_policy.md` | **New file** (this document) | Formal writer storage policy contract |
| `Libraries/Documentation/library_api_contract.md` | Append this contract | Add to existing API contract hierarchy |
| `generate_docs.py` | Update Section 17/18 content | Reflect policy taxonomy in docs generation |
| `docs.html` | Regenerate from generate_docs.py | Update public specification |
| `libraries.html` | Regenerate from generate_docs.py | Update library documentation |
| `AGENTS.md` | Update freeze verdict | Record this contract as frozen


---

## 15. Unresolved Questions

None identified. All four policies are derived from and constrained by the frozen MODERN/ENTERPRISE wire-mode rules. No new protocol semantics are introduced.

---

**READY FOR WRITER STORAGE POLICY CONTRACT FREEZE**
