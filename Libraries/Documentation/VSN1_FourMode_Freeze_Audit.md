# VSN Four-Mode Semantic Freeze Audit

**Verdict: BLOCKED** — not ready for normative freeze as a four-mode architecture.

## 1. Root-cause finding (the real blocker)
The four names (HIGHLY_VERTICAL / VERTICAL / HORIZONTAL / HIGHLY_HORIZONTAL) appear ONLY in the
"informative" overview (generate_docs.py:56 & :225, docs.html:56 & :222). The normative Mode
registry (generate_docs.py:820-833, docs.html:817-830) defines EXACTLY TWO modes:
    Mode 0x01 = MODERN (Vertical)       [active]
    Mode 0x02 = ENTERPRISE (Horizontal) [active]
    Mode 0x00, 0x03-0xFF = reserved     [appearing on wire is malformed]
VR-16 (gen:835): reserved/unknown mode = MALFORMED, MUST NOT be guessed. IV-09 (gen:1090 / docs:1085):
Mode 0x03 -> MALFORMED_CONTAINER. => HIGHLY_* have NO normative value, definition, or vector.

## 2. Four-mode matrix (informative overview only)
| Property | HIGHLY_VERTICAL | VERTICAL | HORIZONTAL | HIGHLY_HORIZONTAL |
|---|---|---|---|---|
| EXTENTS-1 | Allowed | Allowed | Limited/shallow | Forbidden |
| DIRECT-1 | Allowed | Allowed | Preferred | Required |
| Chunking | Allowed | Allowed | Limited | No |
| Deep deps | Allowed w/ limits | Limited | Avoided | Forbidden |
| Compression | Allowed | Allowed | Optional | Not required / canonical baseline |
| Normative mode value | NONE | NONE | NONE | NONE |

## 3. Independent verification (corrects the prior context)
- Compression: RESOLVED, not a blocker. VR-25 (representational, MUST round-trip, GR-45);
  Compression Id 0x00=IDENTITY baseline (gen:783); UNSUPPORTED_TRANSFORM 0x0007 keeps framing
  intact; "wrappers NOT required for canonical recovery" (docs:157); gen:1069 encoder-side only.
- ObjectSerial preservation: RESOLVED. ID-03/ID-09/ID-61/SR-37: repack/compression/mode change
  MUST NOT renumber ObjectSerial.
- Writer-mode vs reader-capability: ADDRESSED. docs:56 + SR-04 (gen:651): mode = representation
  architecture selector, not reader capability.
- "Mixed-policy container": NOT a spec concept. ModeDeclaration is "exactly 1; second is
  malformed (GR-39)" (gen:624); RC-39 forbids changing a container's mode. Containers are single-mode.

## 4. Documentation / structural issues (real, secondary)
- One spec, two conflicting vocabularies: 4-name overview vs 2-value normative registry.
- gen:225 says "Section 11 - Modern and Enterprise" is normative, but the headline (Section 2)
  is the four-mode overview. A reader cannot tell which is authoritative.
- libraries.html:84-85 duplicates a section: "19 Storage Optimization" AND "20 Storage
  optimization" (same topic, different case). libraries.html:352 (Section 18) is a 1-line stub.
- gen:205 maps MODERN/VERTICAL and ENTERPRISE/HORIZONTAL but never defines what HIGHLY_* adds.

## 5. Decisions required to unblock the freeze
1. Pick the authoritative model:
   (a) 2 normative modes (MODERN, ENTERPRISE) + the 4 names as INFORMATIVE aliases over an
       optimization-configuration layer (matches the current normative core; recommended); OR
   (b) 4 normative modes -> allocate mode values 0x03/0x04 for HIGHLY_VERTICAL/HIGHLY_HORIZONTAL,
       add GR/SR/VR rules, and add frozen test vectors.
2. Reconcile the "informative overview" (4 names) with the "normative registry" (2 values) so the
   overview cannot be read as normative.
3. Fix section cross-references and the libraries.html 19/20 duplication.

## 6. Conformance tests (post-decision)
- T1 (model b): Mode 0x03 (HIGHLY_VERTICAL) decodes with EXTENTS-1 / COPY / LITERAL.
- T2 (model b): Mode 0x04 (HIGHLY_HORIZONTAL) is DIRECT-1 only, directly recoverable, EXTENTS-1 forbidden.
- T3 (either model, regression): Mode 0x03 on wire MUST -> MALFORMED_CONTAINER (IV-09).
- T4: a DIRECT-1-only reader reports UNSUPPORTED_TRANSFORM / unsupported-representation on an
  EXTENTS-1 object, keeping framing intact (NOT treated as corruption).
- T5: ObjectSerial unchanged across MODERN->ENTERPRISE repack (ID-03 / SR-37).
- T6: a second ModeDeclaration MUST be malformed (GR-39).

## 7. Final recommendation
NO - not ready. The blocker is the normative/informative split: the 4-mode names have no normative
mode value, while the normative core is a 2-mode (MODERN/ENTERPRISE) system that explicitly marks a
third/fourth mode malformed. Compression and ObjectSerial are already well-specified and are NOT
blockers. Choose model (a) or (b) in Section 5, then re-run the freeze.

