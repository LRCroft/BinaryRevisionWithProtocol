/**
 * Executable LimitCleanUp probe for the TypeScript library.
 *
 * This does NOT merely check that a method named limitCleanup exists. It performs
 * a real 10-revision history, runs the operation, and verifies the resulting
 * revision history, the retained identities, recovery, and argument rejection.
 *
 * Prints a machine-readable final line:
 *    LIMIT_CLEANUP <PASS|FAIL> removed=<csv> retained=<csv>
 */
import {
  VsnStore, VsnError, create, recover,
} from "../JavaScript-TypeScript/src/index.js";

const failures: string[] = [];
function check(cond: boolean, label: string): void {
  if (!cond) failures.push(label);
}

function build(n: number, path = "a.txt"): { store: VsnStore; fid: Buffer } {
  const store = create();
  const fid = store.createFile(path, Buffer.from("v1"));
  for (let i = 2; i <= n; i++) store.writeFile(fid, Buffer.from(`v${i}`));
  return { store, fid };
}

// --- 1-8: real container, 10 revisions, limitCleanup(file, 5) ---------------
const { store, fid } = build(10);
const before = new Map(store.listRevisions(fid).map(
  (r) => [r, store.getRevision(r).objectSerial] as const));
const removed = store.limitCleanup(fid, 5);
const retained = store.listRevisions(fid);
check(removed.length === 5, `exactly 5 removed, got ${removed.length}`);
check(retained.length === 5, `exactly 5 retained, got ${retained.length}`);
check(JSON.stringify(removed) === JSON.stringify([1, 2, 3, 4, 5]),
      `removed ids, got ${JSON.stringify(removed)}`);
check(JSON.stringify(retained) === JSON.stringify([6, 7, 8, 9, 10]),
      `retained ids, got ${JSON.stringify(retained)}`);

// 6: ObjectSerials of retained revisions
for (const r of retained)
  check(store.getRevision(r).objectSerial === before.get(r),
        `retained ObjectSerial ${r} unchanged`);

// 7: deleted revisions are inaccessible
try {
  store.getRevision(1);
  check(false, "deleted revision 1 still accessible");
} catch (e) {
  check((e as VsnError).code === 0x0009,
        `deleted revision raises 0x0009, got 0x${((e as VsnError).code ?? 0).toString(16)}`);
}

// 8: FileHead
const head = store.getCurrentRevision(fid);
check(head === retained[retained.length - 1] && head === 10,
      `FileHead is newest retained, got ${head}`);

// 9: close / reopen
const data = store.commit();
const reopened = new VsnStore(data);
check(JSON.stringify(reopened.listRevisions(fid)) === JSON.stringify(retained),
      "reopen lists retained set");
check(reopened.getCurrentRevision(fid) === 10, "reopened FileHead");
for (const gone of [1, 2, 3, 4, 5]) {
  try {
    reopened.getRevision(gone);
    check(false, `deleted revision ${gone} accessible after reopen`);
  } catch { /* expected */ }
}

// 10: recovery
const rec = recover(data);
check(rec.recovered, "recovery succeeded");
check(rec.acceptedGeneration === store.generation, "recovery generation matches");

// 11-12: idempotency, three calls
for (let i = 0; i < 3; i++)
  check(reopened.limitCleanup(fid, 5).length === 0,
        `repeat call ${i + 1} must remove nothing`);
check(JSON.stringify(reopened.listRevisions(fid)) === JSON.stringify(retained),
      "retained set stable");
check(recover(reopened.commit()).recovered, "recovery after repeated cleanup");

// 13: limit greater than history
const fresh = build(3);
check(fresh.store.limitCleanup(fresh.fid, 99).length === 0,
      "limit > history removes nothing");
check(fresh.store.listRevisions(fresh.fid).length === 3, "limit > history keeps all");

// 14: limit 0 rejected
try {
  reopened.limitCleanup(fid, 0);
  check(false, "limit 0 was not rejected");
} catch (e) {
  check((e as VsnError).code === 0x000C,
        `limit 0 rejected 0x000C, got 0x${((e as VsnError).code ?? 0).toString(16)}`);
}
check(JSON.stringify(reopened.listRevisions(fid)) === JSON.stringify(retained),
      "history unchanged after reject");

// 15: an unrelated file must not be changed
const two = build(6, "a.txt");
const fb = two.store.createFile("b.txt", Buffer.from("b1"));
for (let i = 2; i <= 5; i++) two.store.writeFile(fb, Buffer.from(`b${i}`));
const bBefore = two.store.listRevisions(fb);
const bContent = two.store.readFile(fb);
two.store.limitCleanup(two.fid, 2);
check(JSON.stringify(two.store.listRevisions(fb)) === JSON.stringify(bBefore),
      "unrelated file revisions unchanged");
check(two.store.readFile(fb).equals(bContent), "unrelated file content unchanged");

const status = failures.length === 0 ? "PASS" : "FAIL";
console.log(`LIMIT_CLEANUP ${status} removed=${removed.join(",")} ` +
            `retained=${retained.join(",")}`);
for (const f of failures) console.log("  FAIL: " + f);
process.exit(failures.length === 0 ? 0 : 1);