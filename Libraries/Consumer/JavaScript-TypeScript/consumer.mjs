/* Independent consumer via ESM (named imports) to prove the CJS build is
 * importable by ESM consumers through Node's CJS module interop. */
import { create, VsnStore, validateContainer, StoragePolicy, MODE_MODERN } from "vsn-typescript";

let failures = 0;
const assert = (c, m) => { if (!c) { failures++; console.error("FAIL: " + m); } else console.log("ok  - " + m); };

const s = create(MODE_MODERN);
const fid = s.createFile("esm.txt", Buffer.from("ESM-INTEROP"));
assert(s.fileExists(fid), "ESM: file exists");
assert(Buffer.compare(s.readFile(fid), Buffer.from("ESM-INTEROP")) === 0, "ESM: read round-trips");
const data = s.commit();
assert(validateContainer(data, "Full").length === 0, "ESM: Full validation clean");
assert(StoragePolicy.VERTICAL === 2, "ESM: StoragePolicy.VERTICAL === 2");
assert(VsnStore != null, "ESM: VsnStore class is exported");

console.log(failures === 0 ? "CONSUMER JS/TS (ESM) PASS" : "CONSUMER JS/TS (ESM) FAIL (" + failures + ")");
process.exit(failures === 0 ? 0 : 1);