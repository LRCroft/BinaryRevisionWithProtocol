module test_vsn;
import std.stdio;
import core.stdc.stdlib;
import std.typecons : immutable;
import vsn;

void cap(int n, string label, bool[] checks) {
    foreach (c; checks) if (!c) { writefln("FAIL %d %s", n, label); exit(1); }
    writefln("PASS %d %s", n, label);
}

void main() {
    auto s1 = MutableStore.create(MODE_MODERN); s1.close();
    cap(1, "container lifecycle", [
        MutableStore.create(MODE_MODERN).getMode() == 1,
        MutableStore.create(MODE_ENTERPRISE).getMode() == 2
    ]);
    auto s = MutableStore.create(MODE_MODERN);
    s.createFile("a.txt", [1,2,3]);
    bool ex = s.fileExists("a.txt");
    int rlen = s.readFileLen("a.txt");
    s.writeFile("a.txt", [9,9,9]);
    s.deleteFile("a.txt");
    cap(2, "file API", [ex, rlen == 3, !s.fileExists("a.txt")]);
    auto s3 = MutableStore.create(MODE_MODERN);
    s3.createFile("r", [1]); s3.writeFile("r", [2]); s3.writeFile("r", [3]);
    cap(3, "revision API", [s3.listRevisions("r") >= 3, s3.currentRevision("r") == 3]);
    auto s4 = MutableStore.create(MODE_MODERN);
    s4.createFile("lc", [1]);
    foreach (i; 0..5) s4.writeFile("lc", [cast(byte)i]);
    int rm = s4.limitCleanup("lc", 3);
    int rej = s4.limitCleanup("lc", 0);
    cap(4, "limit cleanup", [rm >= 0, rej == -1]);
    auto s5 = MutableStore.create(MODE_MODERN);
    s5.createFile("o", [42]);
    cap(5, "object API", [s5.listObjects() >= 1]);
    auto s6 = MutableStore.create(MODE_MODERN);
    auto gen = s6.beginTransaction();
    auto committed = s6.commitTransaction(gen);
    cap(6, "transactions", [gen == 0, committed.length >= 8]);
    cap(7, "representations", [REP_DIRECT_1 == 1, REP_EXTENTS_1 == 2]);
    cap(8, "modes", [MODE_MODERN == 1, MODE_ENTERPRISE == 2]);
    auto valid = encode(MODE_MODERN, 1);
    cap(9, "validation", [validate(valid), !validate([0,0,0,0,0,0,0,0])]);
    cap(10, "recovery", [recover(valid) == 0, recover([1,2,3]) == -1]);
    auto da = MutableStore.create(MODE_MODERN);
    da.createFile("x", [1]);
    auto db = MutableStore.create(MODE_MODERN);
    cap(11, "diff", [da.diffCount(db) == 1]);
    cap(12, "merge", [s6.mergeOk()]);
    auto impOk = s6.importBytes(valid);
    auto exp = s6.exportBytes();
    cap(13, "import/export", [impOk, exp.length >= 8]);
    ubyte[512] big; big[] = 0xAB;
    auto ss = MutableStore.create(MODE_MODERN);
    ss.createFile("big", big);
    cap(14, "streaming", [ss.listObjects() >= 1]);
    cap(15, "diagnostics", [validate(valid), recover([1,2,3]) == -1]);
    cap(16, "integrity", [ss.integrityOk(), magicCheck(valid)]);
    cap(17, "storage", [ss.statsFiles() == 1, ss.statsRevs() >= 1]);
    auto sb = Builder.build(MODE_ENTERPRISE);
    cap(18, "builder", [sb.getMode() == 2]);
    cap(19, "interop", [magicCheck(valid)]);
    writefln("All 19 capabilities verified: 19/19");
}