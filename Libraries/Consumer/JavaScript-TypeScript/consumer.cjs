"use strict";
/* Independent consumer of the BUILT vsn-typescript package (CommonJS).
 * Simulates the Campus Workbench VS Code Extension Host (CJS context) resolving
 * the package by name through node_modules — no source files are copied here. */
const fs = require("node:fs");
const path = require("node:path");
const vsn = require("vsn-typescript");

let failures = 0;
function assert(cond, msg) {
  if (!cond) { failures++; console.error("FAIL: " + msg); }
  else console.log("ok  - " + msg);
}

// 1. Lifecycle: create (MODERN) -> write -> read -> commit -> reopen
const store = vsn.create(vsn.MODE_MODERN);
const fid = store.createFile("hello.txt", Buffer.from("VSN-CONSUMER-0123"));
assert(store.fileExists(fid), "file exists after createFile");
assert(Buffer.compare(store.readFile(fid), Buffer.from("VSN-CONSUMER-0123")) === 0, "readFile round-trips content");

// 2. Revisions: two writes => 3 revisions
store.writeFile(fid, Buffer.from("v2-content"));
store.writeFile(fid, Buffer.from("v3-content"));
assert(store.listRevisions(fid).length >= 3, "three revisions tracked");

// 3. LimitCleanUp: keep 2 => removes >= 1
const removed = store.limitCleanup(fid, 2);
assert(Array.isArray(removed) && removed.length >= 1, "limitCleanup removed >= 1 revision");
assert(store.listRevisions(fid).length <= 2, "revisions now <= 2");

// 4. Commit -> validate (Full, clean) -> recover
const data = store.commit();
assert(Buffer.isBuffer(data) && data.length >= 8, "commit produced canonical bytes");
assert(vsn.validateContainer(data, "Full").length === 0, "Full validation is clean");
const rec = vsn.recoverContainer(data);
assert(rec != null, "recoverContainer returns a result");

// 5. Reopen round-trip via the package's public open API
const st2 = vsn.VsnStore.open(data);
assert(st2.getFileId("hello.txt") != null, "reopened store exposes file by path");

// 6. Diff
const a = vsn.create(1); a.createFile("x.txt", Buffer.from("A"));
const b = vsn.create(1); b.createFile("x.txt", Buffer.from("B")); b.createFile("y.txt", Buffer.from("C"));
const d = vsn.diff.diffFiles(a, b);
assert(d.modified.includes("x.txt") && d.added.includes("y.txt"), "diff detects modified + added files");

// 7. Three-way merge: conflict + clean (ancestor-on-ours)
const base = vsn.create(1); base.createFile("f.txt", Buffer.from("base"));
const ours = vsn.create(1); ours.createFile("f.txt", Buffer.from("ours"));
const theirs = vsn.create(1); theirs.createFile("f.txt", Buffer.from("theirs"));
assert(vsn.merge.hasConflicts(vsn.merge.threeWayMerge(base, ours, theirs)), "conflicting merge reports a conflict");
const ours2 = vsn.create(1); ours2.createFile("f.txt", Buffer.from("base"));
assert(!vsn.merge.hasConflicts(vsn.merge.threeWayMerge(base, ours2, theirs)), "ancestor-on-ours merges cleanly");

// 8. Import / Export
const imp = vsn.create(1);
const ifid = vsn.importFile(imp, "imp.txt", Buffer.from("imported"));
assert(Buffer.compare(vsn.exportFile(imp, ifid), Buffer.from("imported")) === 0, "import/export round-trips");

// 9. Integrity + canonical hash
const report = vsn.verifyIntegrity(imp);
assert(report != null && Array.isArray(report.errors), "verifyIntegrity returns a report");
assert(/^[0-9a-f]{64}$/.test(vsn.canonicalHash(data)), "canonicalHash is a sha256 hex digest");

// 10. Stats / inspect
const info = vsn.inspectContainer(a);
assert(info != null && typeof info.fileCount === "number", "inspectContainer reports fileCount");

// 11. StoragePolicy + wire-mode constants
assert(vsn.StoragePolicy.HIGHLY_VERTICAL === 1 && vsn.StoragePolicy.HIGHLY_HORIZONTAL === 4, "StoragePolicy values 1..4");
assert(vsn.MODE_MODERN === 1 && vsn.MODE_ENTERPRISE === 2, "wire modes 1/2");

// 11b. Storage Policy wire-in: public createWithPolicy -> commit -> public parse -> policy read back.
assert(vsn.StoragePolicy.HIGHLY_VERTICAL === 1 && vsn.StoragePolicy.VERTICAL === 2 && vsn.StoragePolicy.HORIZONTAL === 3, "SP values 1..3");
let allRT = true;
for (const [pol, exp] of [[1, 1], [2, 2], [3, 3], [4, 4]]) {
  const st = vsn.VsnStore.createWithPolicy(pol);
  st.createFile("js.txt", Buffer.from("POL"));
  const parsed = vsn.parse(st.commit());
  if (parsed.storagePolicy !== exp) { allRT = false; break; }
}
assert(allRT, "SP wire-in: all 4 policies round-trip through public parse");
const jb1 = vsn.VsnStore.createWithPolicy(3).commit();
const jb2 = vsn.VsnStore.createWithPolicy(1).commit();
assert(Buffer.compare(jb1, jb2) !== 0, "distinct policies -> distinct wire bytes");

// 12. Cross-language interop: load a C-produced frozen vector and validate it
const tv = process.env.VSN_TESTVECTORS;
if (tv) {
  const dv = fs.readFileSync(path.join(tv, "DIRECT-02.vsn"));
  assert(vsn.validateContainer(dv, "Structural").length === 0, "frozen DIRECT-02 validates");
  assert(vsn.recoverContainer(dv) != null, "frozen DIRECT-02 recovers");
} else {
  console.log("skip  - VSN_TESTVECTORS not set (interop step)");
}

console.log(failures === 0 ? "CONSUMER JS/TS PASS" : "CONSUMER JS/TS FAIL (" + failures + ")");
process.exit(failures === 0 ? 0 : 1);