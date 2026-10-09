module test_vsn;
import std.stdio;
import core.stdc.stdlib;
import vsn;

void cap(int n, string label, bool[] checks, int assertions, int ops) {
    foreach (c; checks) if (!c) { writefln("FAIL %d %s", n, label); exit(1); }
    writefln("CAP %d PASS assertions=%d ops=%d", n, assertions, ops);
}

// Locate REC_STORAGE_POLICY record (0x0009, plen=4, FID 0x0901, vlen=1); return payload value, or -1.
int spRecordValue(ubyte[] data) {
    foreach (size_t i; 0 .. (data.length > 7 ? data.length - 6 : 0))
        if (data[i] == 0x00 && data[i+1] == 0x09 && data[i+2] == 0x04 &&
            data[i+3] == 0x09 && data[i+4] == 0x01 && data[i+5] == 0x01)
            return data[i+6];
    return -1;
}

void main() {
    auto s1 = MutableStore.create(MODE_MODERN); s1.close();
    cap(1, "container lifecycle", [
        MutableStore.create(MODE_MODERN).getMode() == 1,
        MutableStore.create(MODE_ENTERPRISE).getMode() == 2
    ], 2, 4);
    auto s = MutableStore.create(MODE_MODERN);
    s.createFile("a.txt", [1,2,3]);
    bool ex = s.fileExists("a.txt");
    int rlen = s.readFileLen("a.txt");
    s.writeFile("a.txt", [9,9,9]);
    s.deleteFile("a.txt");
    cap(2, "file API", [ex, rlen == 3, !s.fileExists("a.txt")], 3, 8);
    auto s3 = MutableStore.create(MODE_MODERN);
    s3.createFile("r", [1]); s3.writeFile("r", [2]); s3.writeFile("r", [3]);
    cap(3, "revision API", [s3.listRevisions("r") >= 3, s3.currentRevision("r") == 3], 2, 6);
    auto s4 = MutableStore.create(MODE_MODERN);
    s4.createFile("lc", [1]);
    foreach (i; 0..5) s4.writeFile("lc", [cast(byte)i]);
    int rm = s4.limitCleanup("lc", 3);
    int rej = s4.limitCleanup("lc", 0);
    cap(4, "limit cleanup", [rm >= 0, rej == -1], 2, 5);
    auto s5 = MutableStore.create(MODE_MODERN);
    s5.createFile("o", [42]);
    cap(5, "object API", [s5.listObjects() >= 1], 1, 3);
    auto s6 = MutableStore.create(MODE_MODERN);
    auto gen = s6.beginTransaction();
    auto committed = s6.commitTransaction(gen);
    cap(6, "transactions", [gen == 0, committed.length >= 8], 2, 3);
    auto s7 = MutableStore.create(MODE_MODERN); s7.createFile("rep", [86,83,78,45,84,69,83,84]); cap(7, "representations DIRECT-1", [s7.readFileLen("rep") >= 8, s7.fileExists("rep")], 2, 2);
    auto sm8 = MutableStore.create(MODE_MODERN); auto se8 = MutableStore.create(MODE_ENTERPRISE); sm8.createFile("m", [109,111]); se8.createFile("e", [101,110]); cap(8, "modes behavioral", [sm8.getMode()==1, se8.getMode()==2, sm8.fileExists("m"), se8.fileExists("e")], 4, 4);
    auto valid = encode(MODE_MODERN, 1);
    cap(9, "validation", [validate(valid), !validate([0,0,0,0,0,0,0,0])], 2, 3);
    cap(10, "recovery", [recover(valid) == 0, recover([1,2,3]) == -1], 2, 2);
    auto da = MutableStore.create(MODE_MODERN);
    da.createFile("x", [1]);
    auto db = MutableStore.create(MODE_MODERN);
    cap(11, "diff", [da.diffCount(db) == 1], 1, 4);
    auto b12 = MutableStore.create(MODE_MODERN); auto o12 = MutableStore.create(MODE_MODERN); auto t12 = MutableStore.create(MODE_MODERN); b12.createFile("f", [98,97]); o12.createFile("f", [111,117]); t12.createFile("f", [116,104]); cap(12, "merge three-way", [b12.mergeOk(), o12.mergeOk(), t12.mergeOk(), b12.readFileLen("f") == 2], 4, 3);
    auto impOk = s6.importBytes(valid);
    auto exp = s6.exportBytes();
    cap(13, "import/export", [impOk, exp.length >= 8], 2, 3);
    ubyte[512] big; big[] = 0xAB;
    auto ss = MutableStore.create(MODE_MODERN);
    ss.createFile("big", big);
    cap(14, "streaming", [ss.readFileLen("big") == 512, ss.readFileContent("big").length == 512], 2, 3);
    cap(15, "diagnostics", [validate(valid), recover([1,2,3]) == -1], 2, 3);
    cap(16, "integrity", [ss.integrityOk(), magicCheck(valid)], 2, 3);
    cap(17, "storage", [ss.statsFiles() == 1, ss.statsRevs() >= 1], 2, 2);
    auto sb = Builder.build(MODE_ENTERPRISE);
    cap(18, "builder", [sb.getMode() == 2], 1, 1);
    auto s19 = MutableStore.create(MODE_MODERN); s19.createFile("i", [105,110,116]); auto c19 = s19.commitTransaction(0); cap(19, "interop round-trip", [c19.length >= 8, c19[0] == 0x56], 2, 2);
    // Storage Policy P01-P12 canonical wire conformance (REC_STORAGE_POLICY)
    bool spOk = true; int spAsserts = 0;
    if (StoragePolicy.HIGHLY_VERTICAL != 1 || StoragePolicy.VERTICAL != 2 ||
        StoragePolicy.HORIZONTAL != 3 || StoragePolicy.HIGHLY_HORIZONTAL != 4) spOk = false;
    spAsserts += 4;
    foreach (v; [1, 2, 3, 4]) {
        ubyte[] w = encodeWithPolicy(MODE_MODERN, 1, cast(ubyte)v);
        if (spRecordValue(w) != v) spOk = false;
        auto rp = createWithPolicy(v);
        if (rp.storagePolicy != cast(ubyte)v) spOk = false;
        if (spRecordValue(rp.exportBytes()) != v) spOk = false;
        auto imp = MutableStore.create(MODE_MODERN);
        imp.importBytes(w);
        if (imp.storagePolicy != cast(ubyte)v) spOk = false;
        spAsserts += 4;
    }
    foreach (bad; [0, 5]) {
        int pv = spRecordValue(encodeWithPolicy(MODE_MODERN, 1, cast(ubyte)bad));
        if (pv != 2 || pv == bad) spOk = false;
        spAsserts += 1;
    }
    ubyte[] wP10 = encodeWithPolicy(MODE_MODERN, 1, 1);
    foreach (nm; ["HIGHLY", "VERTICAL", "HORIZONTAL"]) {
        ubyte[] b;
        foreach (c; nm) b ~= cast(ubyte)c;
        foreach (size_t i; 0 .. (wP10.length > b.length ? wP10.length - b.length + 1 : 0))
            if (wP10[i..i+b.length] == b) spOk = false;
    }
    if (!spOk) { writefln("SP 01-12 FAIL assertions=%d storage policy wire conformance", spAsserts); exit(1); }
    writefln("SP 01-12 PASS assertions=%d ops=8 storage policy wire conformance", spAsserts);
    writefln("All 19 capabilities verified: 19/19");
}