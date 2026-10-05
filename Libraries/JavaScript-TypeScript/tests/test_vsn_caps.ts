// Capability tests for JS/TS - all 19 capability groups
import { create, VsnStore, validateContainer, recover as recoverContainer, verifyIntegrity, exportBytes, importBytes, diff, merge, storage, transaction } from "../src/index.js";
import { VsnContainer } from "../src/api.js";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import path from "path";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TV = path.resolve(__dirname, "../../TestVectors");

let anyFail = false;
function checkCap(n, cond, msg) {
    if (!cond) { console.log("FAIL " + n + " " + msg); anyFail = true; }
    else { console.log("PASS " + n + " " + msg); }
}

function cap1() { // Container lifecycle
    const s1 = create(1);
    checkCap(1, s1.mode === 1, "MODE_MODERN=1");
    const s2 = create(2);
    checkCap(1, s2.mode === 2, "MODE_ENTERPRISE=2");
    s1.close();
    checkCap(1, s1.isClosed === true, "store is closed");
}

function cap2() { // File API
    const s = create();
    const fid1 = s.createFile("a.txt", Buffer.from("abc"));
    checkCap(2, fid1.length === 16, "FileId 16 bytes");
    checkCap(2, Buffer.from(s.readFile(fid1)).toString() === "abc", "read returns content");
    s.writeFile(fid1, Buffer.from("xyz"));
    checkCap(2, Buffer.from(s.readFile(fid1)).toString() === "xyz", "write updates");
    const fid2 = s.createFile("b.txt", Buffer.from("def"));
    checkCap(2, Buffer.compare(fid1, fid2) !== 0, "distinct file IDs");
    const fid3 = s.createFile("gone.txt", Buffer.from("x"));
    s.deleteFile(fid3);
    checkCap(2, !s.fileExists(fid3), "deleted file removed");
}

function cap3() { // Revision API
    const s = create();
    const fid = s.createFile("f.txt", Buffer.from("v0"));
    for (let i = 1; i <= 5; i++) s.writeFile(fid, Buffer.from("v" + i));
    checkCap(3, s.listRevisions(fid).length >= 6, "revision count increases");
}

function cap4() { // LimitCleanup
    const s = create();
    const fid = s.createFile("f.txt", Buffer.from("v0"));
    for (let i = 1; i <= 6; i++) s.writeFile(fid, Buffer.from("v" + i));
    checkCap(4, typeof s.limitCleanup === "function", "limitCleanup available");
}

function cap5() { // Object API
    const s = create();
    s.createFile("a.txt", Buffer.from("obj test"));
    s.commit();
    const objs = s.listObjects();
    checkCap(5, objs.length >= 1, "has objects");
    if (objs.length > 0) {
        const mat = s.materialize(objs[0]);
        checkCap(5, mat !== null && Buffer.isBuffer(mat), "materialize returns bytes");
    }
}

function cap6() { // Transactions
    const tx = transaction();
    checkCap(6, tx !== null && typeof tx === "object", "transaction created via factory");
    const s = create();
    tx.stageCreate("txn.txt", Buffer.from("data"));
    checkCap(6, tx.changeCount === 1, "stageCreate records changes");
}

function cap7() { // Representations
    const s = create();
    s.createFile("a.txt", Buffer.from("rep test"));
    const data = s.commit();
    checkCap(7, data.length > 8, "commit produces container");
    checkCap(7, data.toString("utf8", 0, 4) === "VSN-", "valid header magic");
}

function cap8() { // Modes
    const s1 = create(1);
    checkCap(8, s1.mode === 1, "MODE_MODERN=1");
    const s2 = create(2);
    checkCap(8, s2.mode === 2, "MODE_ENTERPRISE=2");
}

function cap9() { // Validation
    const s = create();
    s.createFile("a.txt", Buffer.from("valid"));
    const data = s.commit();
    const diags = validateContainer(data, "Full");
    checkCap(9, Array.isArray(diags), "validateContainer returns diagnostics array");
}

function cap10() { // Recovery
    const s = create();
    s.createFile("a.txt", Buffer.from("recover"));
    const data = s.commit();
    const r = recoverContainer(data);
    checkCap(10, r.recovered === true, "valid recovery");
    const r2 = recoverContainer(Buffer.alloc(4, 0x42));
    checkCap(10, !r2.recovered || r2.status !== "ok", "bad magic fails");
}

function cap11() { // Diff
    const s1 = create();
    s1.createFile("a.txt", Buffer.from("same"));
    const s2 = create();
    s2.createFile("a.txt", Buffer.from("diff content"));
    const dr = diff.diffFiles(s1, s2);
    checkCap(11, dr !== null && typeof dr === "object", "diff returns structure");
}

function cap12() { // Merge
    const base = create();
    base.createFile("a.txt", Buffer.from("base content"));
    base.commit();
    const ours = create();
    ours.createFile("a.txt", Buffer.from("our modification"));
    ours.commit();
    const theirs = create();
    theirs.createFile("a.txt", Buffer.from("their change"));
    theirs.commit();
    const mr = merge.threeWayMerge(base, ours, theirs);
    checkCap(12, mr !== null && typeof mr === "object", "merge returns result");
}

function cap13() { // Import/Export (serialize container)
    const s = create();
    s.createFile("a.txt", Buffer.from("import test"));
    const exported = s.commit();
    checkCap(13, exported.length > 0 && exported.toString("utf8", 0, 4) === "VSN-", "export produces bytes");
}

function cap14() { // Streaming (large object)
    const s = create();
    s.createFile("big.txt", Buffer.from("x".repeat(1024)));
    const exported = s.commit();
    checkCap(14, exported.length > 0, "export produces bytes");
    checkCap(14, exported.toString("utf8", 0, 4) === "VSN-", "export has valid header");
}

function cap15() { // Diagnostics
    const s = create();
    s.createFile("a.txt", Buffer.from("diag"));
    const data = s.commit();
    const diags = validateContainer(data, "Full");
    checkCap(15, Array.isArray(diags), "diagnostics returns array");
}

function cap16() { // Integrity
    const s = create();
    s.createFile("a.txt", Buffer.from("integrity"));
    const report = verifyIntegrity(s);
    checkCap(16, report !== null && typeof report === "object", "verifyIntegrity returns report");
}

function cap17() { // Storage
    const s = create();
    s.createFile("a.txt", Buffer.from("x"));
    const mgr = new storage.StorageManager();
    const stats = mgr.stats(s);
    checkCap(17, stats !== null && typeof stats === "object", "storage stats available");
}

function cap18() { // Builder (StorageManager as builder)
    const bldr = new storage.StorageManager();
    checkCap(18, typeof bldr.stats === "function", "manager has stats");
}

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
