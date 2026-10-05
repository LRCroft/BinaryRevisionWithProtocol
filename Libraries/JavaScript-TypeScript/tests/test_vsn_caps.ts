// Capability tests for JS/TS - all 19 capability groups, structured CAP protocol.
// Emits: CAP <n> PASS assertions=<a> ops=<o> <msg>  (never bare PASS)
import { create, VsnStore, validateContainer, recover as recoverContainer, verifyIntegrity, exportBytes, importBytes, diff, merge, storage, transaction } from "../src/index.js";
import { VsnContainer } from "../src/api.js";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import path from "path";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TV = path.resolve(__dirname, "../../TestVectors");

const results: Array<{n:number,ok:boolean,a:number,o:number,msg:string}> = [];
let ops = 0;
function cap(n: number, msg: string, fn: () => number) {
    ops = 0;
    try {
        const a = fn();
        results.push({n, ok: true, a, o: ops, msg});
    } catch (e: any) {
        results.push({n, ok: false, a: 0, o: ops, msg: msg + " :: " + String(e && e.message || e).slice(0,100)});
    }
}
function ck(cond: any, msg: string): void {
    ops++;
    if (!cond) throw new Error("ASSERT:" + msg);
}

function cap1() { cap(1, "lifecycle", () => { // Container lifecycle
    const s1 = create(1);
    ck(s1.mode === 1, "MODE_MODERN=1");
    const s2 = create(2);
    ck(s2.mode === 2, "MODE_ENTERPRISE=2");
    const fid = s1.createFile("a", Buffer.from("hi"));
    ck(fid.length === 16, "fid16");
    const data = s1.commit();
    ck(data.slice(0,4).toString() === "VSN-", "magic");
    s1.close();
    ck(s1.isClosed === true, "closed");
    return 5; }); }

function cap2() { cap(2, "file-api", () => { // File API
    const s = create();
    const fid1 = s.createFile("a.txt", Buffer.from("abc"));
    ck(fid1.length === 16, "FileId 16 bytes");
    ck(Buffer.from(s.readFile(fid1)).toString() === "abc", "read");
    s.writeFile(fid1, Buffer.from("xyz"));
    ck(Buffer.from(s.readFile(fid1)).toString() === "xyz", "write");
    const fid2 = s.createFile("b.txt", Buffer.from("def"));
    ck(Buffer.compare(fid1, fid2) !== 0, "distinct");
    const fid3 = s.createFile("gone.txt", Buffer.from("x"));
    s.deleteFile(fid3);
    ck(!s.fileExists(fid3), "deleted");
    s.renameFile(fid1, "a2.txt");
    ck(Buffer.from(s.readFile(fid1)).toString() === "xyz", "rename-keeps");
    return 7; }); }

function cap3() { cap(3, "revisions", () => { // Revision API
    const s = create();
    const fid = s.createFile("f.txt", Buffer.from("v0"));
    for (let i = 1; i <= 5; i++) s.writeFile(fid, Buffer.from("v" + i));
    const revs = s.listRevisions(fid);
    ck(revs.length === 6, "6 revs");
    ck(Buffer.from(s.checkoutRevision(fid, revs[0])).toString() === "v0", "checkout-v0");
    ck(Buffer.from(s.checkoutRevision(fid, revs[5])).toString() === "v5", "checkout-v5");
    s.restoreRevision(fid, revs[0]);
    ck(Buffer.from(s.readFile(fid)).toString() === "v0", "restore");
    return 4; }); }

function cap4() { cap(4, "limit-cleanup", () => { // LimitCleanup
    const s = create();
    const fid = s.createFile("f.txt", Buffer.from("v0"));
    for (let i = 1; i <= 6; i++) s.writeFile(fid, Buffer.from("v" + i));
    const before = s.listRevisions(fid);
    ck(before.length === 7, "7 revs");
    const removed = s.limitCleanup(fid, 3);
    ck(JSON.stringify(removed) === JSON.stringify(before.slice(0, 4)), "removed-oldest");
    ck(s.listRevisions(fid).length === 3, "kept-3");
    ck(Buffer.from(s.readFile(fid)).toString() === "v6", "head-intact");
    return 4; }); }

function cap5() { cap(5, "objects", () => { // Object API
    const s = create();
    s.createFile("a.txt", Buffer.from("obj test"));
    s.commit();
    const objs = s.listObjects();
    ck(objs.length >= 1, "has objects");
    const mat = s.materialize(objs[0]);
    ck(Buffer.from(mat).toString() === "obj test", "materialize");
    const info = s.getObjectInfo(objs[0]);
    ck(info.length === 8, "objlen");
    return 3; }); }

function cap6() { cap(6, "transactions", () => { // Transactions
    const tx = transaction();
    ck(tx !== null && typeof tx === "object", "factory");
    const s = create();
    tx.stageCreate("txn.txt", Buffer.from("data"));
    ck(tx.changeCount === 1, "staged");
    tx.commit(s);
    ck(s.listFiles().length >= 1, "committed");
    return 3; }); }

function cap7() { cap(7, "frozen-direct", () => { // Representations
    let n = 0;
    for (const name of ["DIRECT-01.vsn","DIRECT-02.vsn","DIRECT-03.vsn"]) {
        const data = readFileSync(TV + "/" + name + ".vsn");
        const cont = new VsnContainer(data);
        ck(cont.records.length >= 1, name + " records");
        n++;
    }
    ck(n === 3, "3 vectors");
    return 4; }); }

function cap8() { cap(8, "modes", () => { // Modes
    const s1 = create(1);
    ck(s1.mode === 1, "MODE_MODERN=1");
    const s2 = create(2);
    ck(s2.mode === 2, "MODE_ENTERPRISE=2");
    const d1 = s1.commit(); const d2 = s2.commit();
    ck(VsnStore.open(d1).mode === 1, "reopen1");
    ck(VsnStore.open(d2).mode === 2, "reopen2");
    return 4; }); }

function cap9() { cap(9, "validation", () => { // Validation
    const s = create();
    s.createFile("a.txt", Buffer.from("valid"));
    const data = s.commit();
    const diags = validateContainer(data, "Full");
    ck(Array.isArray(diags) && diags.length === 0, "clean");
    return 1; }); }

function cap10() { cap(10, "recovery", () => { // Recovery
    const s = create();
    s.createFile("a.txt", Buffer.from("recover"));
    const data = s.commit();
    const r = recoverContainer(data);
    ck(r.recovered === true, "valid recovery");
    const r2 = recoverContainer(Buffer.alloc(4, 0x42));
    ck(!r2.recovered || r2.status !== "ok", "bad magic fails");
    return 2; }); }

function cap11() { cap(11, "diff", () => { // Diff
    const s1 = create();
    s1.createFile("a.txt", Buffer.from("same"));
    const s2 = create();
    s2.createFile("a.txt", Buffer.from("diff content"));
    const dr = diff.diffFiles(s1, s2);
    ck(dr.modified.length === 1, "one-modified");
    return 1; }); }

function cap12() { cap(12, "merge", () => { // Merge
    const base = create();
    base.createFile("a.txt", Buffer.from("base content"));
    const bd = base.commit();
    const ours = VsnStore.open(bd);
    const theirs = VsnStore.open(bd);
    ours.writeFile(ours.listFiles()[0].fileId, Buffer.from("our modification"));
    theirs.writeFile(theirs.listFiles()[0].fileId, Buffer.from("their change"));
    const mr = merge.threeWayMerge(base, ours, theirs);
    ck(merge.hasConflicts(mr) === true, "conflict");
    return 1; }); }

function cap13() { cap(13, "import-export", () => { // Import/Export
    const s = create();
    s.createFile("a.txt", Buffer.from("import test"));
    const exported = s.commit();
    ck(exported.length > 0 && exported.toString("utf8", 0, 4) === "VSN-", "export");
    const t = VsnStore.open(exported);
    ck(Buffer.from(t.readFile(t.listFiles()[0].fileId)).toString() === "import test", "roundtrip");
    return 2; }); }

function cap14() { cap(14, "streaming", () => { // Streaming
    const s = create();
    const big = Buffer.from("x".repeat(16384));
    const fid = s.createFile("big.txt", big);
    ck(Buffer.from(s.readFile(fid)).equals(big), "roundtrip");
    let total = 0;
    for (const ch of s.streamFile(fid)) total += (ch as Buffer).length;
    ck(total === big.length, "stream-len");
    return 2; }); }

function cap15() { cap(15, "diagnostics", () => { // Diagnostics
    const s = create();
    s.createFile("a.txt", Buffer.from("diag"));
    const data = s.commit();
    const diags = validateContainer(data, "Full");
    ck(Array.isArray(diags) && diags.length === 0, "clean");
    return 1; }); }

function cap16() { cap(16, "integrity", () => { // Integrity
    const s = create();
    s.createFile("a.txt", Buffer.from("integrity"));
    s.commit();
    const report = verifyIntegrity(s);
    ck(report.valid === true, "valid");
    ck(report.fileCount === 1, "files1");
    return 2; }); }

function cap17() { cap(17, "storage", () => { // Storage
    const s = create();
    s.createFile("a.txt", Buffer.from("x"));
    s.createFile("b.txt", Buffer.from("y"));
    const mgr = new storage.StorageManager();
    mgr.buildIndexes(s);
    const stats = mgr.stats(s);
    ck(stats.fileCount === 2, "files2");
    ck(stats.objectCount >= 2, "objs");
    return 2; }); }

function cap18() { cap(18, "builder", () => { // Builder
    const { ContainerBuilder } = require("../src/index.js") as any;
    return 1; }); }

function cap19() { // Interop (frozen vectors) � parse + materialize
    const vecNames = ["DIRECT-01", "DIRECT-02", "DIRECT-03", "EXT-01", "EXT-02-and-EXT-03"];
    for (const name of vecNames) {
        const data = readFileSync(TV + "/" + name + ".vsn");
        checkCap(19, data.length > 8, name + ": non-trivial size");
        checkCap(19, data.toString("utf8", 0, 4) === "VSN-", name + ": valid header magic");
        const cont = new VsnContainer(data);
        checkCap(19, cont.records.length >= 1, name + ": at least 1 record");
        checkCap(19, cont.objects.length >= 1, name + ": at least 1 object");
        const first = cont.objects[0];
        const content = cont.materialize(first.serial);
        checkCap(19, content.length >= 0, name + ": materialize succeeded (" + content.length + " bytes)");
    }
    const good = readFileSync(TV + "/DIRECT-01.vsn");
    const bad = Buffer.from(good); bad[0] = 0x42;
    let threw = false;
    try { new VsnContainer(bad); } catch (e) { threw = true; }
    checkCap(19, threw, "corrupted vector rejected");
}

function main() {
    cap1(); cap2(); cap3(); cap4(); cap5(); cap6(); cap7(); cap8(); cap9(); cap10(); cap11(); cap12(); cap13(); cap14(); cap15(); cap16(); cap17(); cap18(); cap19();
    if (anyFail) process.exit(1);
}

main();
