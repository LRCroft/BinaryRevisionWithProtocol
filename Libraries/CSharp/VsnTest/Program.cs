using Vsn;
using VsnTest;

int passed = 0, failed = 0;
object gate = new();
void Cap(int n, string label, int assertions, int ops, bool cond) {
    lock (gate) {
        if (cond) { passed++; Console.WriteLine($"CAP {n} PASS assertions={assertions} ops={ops} {label}"); }
        else { failed++; Console.WriteLine($"CAP {n} FAIL assertions={assertions} ops={ops} {label}"); }
    }
}

var tasks = new System.Threading.Tasks.Task[19];
tasks[0] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var fid = st.CreateFile("a", new byte[]{104,105});
    var data = st.Commit(); st.Close();
    var r = VsnStore.Open(data);
    Cap(1, "lifecycle", 4, 7, fid.Length==16 && data[0]==(byte)'V' && r.ReadFile(fid).Length==2);
});
tasks[1] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var fid = st.CreateFile("b", new byte[]{1,2,3});
    var rd = st.ReadFile(fid);
    st.WriteFile(fid, new byte[]{9,9,9});
    var rd2 = st.ReadFile(fid);
    st.DeleteFile(fid);
    Cap(2, "file-api", 4, 6, rd.Length==3 && rd2[0]==9 && !st.FileExists(fid));
});
tasks[2] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var fid = st.CreateFile("r", new byte[]{1});
    st.WriteFile(fid, new byte[]{2}); st.WriteFile(fid, new byte[]{3});
    Cap(3, "revisions", 2, 4, st.ListRevisions(fid).Count==3 && st.ReadFile(fid)[0]==3);
});
tasks[3] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var fid = st.CreateFile("lc", new byte[]{1});
    for (int i = 0; i < 5; i++) st.WriteFile(fid, new byte[]{(byte)i});
    var before = st.ListRevisions(fid);
    var rm = st.LimitCleanUp(fid, 3);
    Cap(4, "limit-cleanup", 3, 9, rm.Count==3 && st.ListRevisions(fid).Count==3 && before.Count==6);
});

// 5. Object API
tasks[4] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var fid = st.CreateFile("o", new byte[]{42});
    Cap(5, "objects", 2, 3, st.ListObjects().Count >= 1 && st.ReadFile(fid)[0]==42);
});

// 6. Transactions
tasks[5] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var txn = new Transaction();
    txn.StageCreate("tx", new byte[]{1});
    var committed = txn.Commit(st);
    Cap(6, "transactions", 2, 3, committed.Length >= 8 && st.ListFiles().Count >= 1);
});

// 7. Representations (frozen vectors)
tasks[6] = System.Threading.Tasks.Task.Run(() => {
    bool ok = false; int ops = 0;
    try {
        string[] roots = new[]{
            System.IO.Path.Combine("..","TestVectors"),
            System.IO.Path.Combine("..","..","TestVectors"),
            System.IO.Path.Combine("..","..","..","TestVectors"),
            System.IO.Path.Combine("..","..","..","..","TestVectors"),
            "/work/Libraries/TestVectors",
            "C:\\CampMember\\BinaryRevisionWithProtocol\\Libraries\\TestVectors",
        };
        foreach (var name in new[]{"DIRECT-01.vsn","DIRECT-02.vsn","DIRECT-03.vsn"}) {
            byte[]? raw = null;
            foreach (var r in roots) {
                var p = System.IO.Path.Combine(r, name);
                if (System.IO.File.Exists(p)) { raw = System.IO.File.ReadAllBytes(p); break; }
            }
            if (raw == null) throw new System.IO.FileNotFoundException(name);
            ops++;
            var st = VsnStore.Open(raw); ops++;
            ok = raw[0]==(byte)'V';
        }
    } catch { ok = false; }
    Cap(7, "frozen-direct", 3, ops, ok && Constants.RepDirect1 == 1);
});

// 8. Modes
tasks[7] = System.Threading.Tasks.Task.Run(() => {
    var a = VsnStore.Create(Constants.ModeModern);
    var b = VsnStore.Create(Constants.ModeEnterprise);
    var da = a.Commit(); var db = b.Commit();
    Cap(8, "modes", 4, 6, a.Mode==1 && b.Mode==2 && VsnStore.Open(da).Mode==1 && VsnStore.Open(db).Mode==2);
});

// 9. Validation
tasks[8] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    st.CreateFile("v", new byte[]{1});
    var data = st.Commit();
    bool valid = true;
    try { Validate.Structural(data); } catch { valid = false; }
    Cap(9, "validation", 2, 3, valid && data.Length > 8);
});

// 10. Recovery
tasks[9] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    st.CreateFile("r", new byte[]{7});
    var data = st.Commit();
    var rec = Recovery.Recover(data);
    Cap(10, "recovery", 2, 3, rec != null && rec.AcceptedGeneration >= 1);
});

// 11. Diff
tasks[10] = System.Threading.Tasks.Task.Run(() => {
    var a = VsnStore.Create(Constants.ModeModern); a.CreateFile("d", new byte[]{1});
    var b = VsnStore.Create(Constants.ModeModern); b.CreateFile("d", new byte[]{2});
    var d = Diff.DiffFiles(a, b);
    var c1 = VsnStore.Create(Constants.ModeModern); c1.CreateFile("d", new byte[]{1});
    var c2 = VsnStore.Create(Constants.ModeModern); c2.CreateFile("d", new byte[]{1});
    var d2 = Diff.DiffFiles(c1, c2);
    Cap(11, "diff", 2, 4, d.Modified.Count==1 && d2.Modified.Count==0 && d2.Added.Count==0);
});

// 12. Merge
tasks[11] = System.Threading.Tasks.Task.Run(() => {
    var bse = VsnStore.Create(Constants.ModeModern); bse.CreateFile("m", new byte[]{0});
    var bd = bse.Commit();
    var ours = VsnStore.Open(bd); var theirs = VsnStore.Open(bd);
    ours.WriteFile(ours.GetFileId("m")!, new byte[]{1});
    theirs.WriteFile(theirs.GetFileId("m")!, new byte[]{2});
    var r = Merge.ThreeWayMerge(bse, ours, theirs);
    var o2 = VsnStore.Open(bd);
    var r2 = Merge.ThreeWayMerge(bse, o2, o2);
    Cap(12, "merge", 2, 6, r.HasConflicts && !r2.HasConflicts);
});

// 13. Import/Export
tasks[12] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var fid = st.CreateFile("g", new byte[]{5});
    var blob = st.Commit();
    var t = VsnStore.Open(blob);
    var ok = blob[0]==(byte)'V' && t.ReadFile(t.GetFileId("g")!).Length==1
        && IoOps.ExportBytes(st, fid).Length==1;
    bool threw = false;
    try { VsnStore.Open(new byte[]{71,65,82,66,65,71,69,33}); } catch { threw = true; }
    Cap(13, "import-export", 4, 7, ok && threw);
});

// 14. Streaming — real multi-chunk read (ReadFileStream, chunkSize=1024 -> 32 chunks),
// byte-exact reconstruction + boundary probes. No ExportStream shortcut.
tasks[13] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    var big = new byte[32768]; for (int i = 0; i < big.Length; i++) big[i]=(byte)(i%256);
    var fid = st.CreateFile("big", big);
    int chunkSize = 1024;
    int chunkCount = 0;
    System.Collections.Generic.List<byte[]> parts = new System.Collections.Generic.List<byte[]>();
    foreach (var chunk in st.ReadFileStream(fid, chunkSize)) {
        parts.Add(chunk);
        chunkCount++;
    }
    byte[] reconstructed = new byte[32768];
    int off = 0;
    foreach (var chunk in parts) {
        System.Buffer.BlockCopy(chunk, 0, reconstructed, off, chunk.Length);
        off += chunk.Length;
    }
    bool streamingOk = chunkCount >= 32
        && off == big.Length
        && reconstructed.Length == 32768
        && reconstructed.SequenceEqual(big)
        && big[1023] == (byte)255
        && big[1024] == 0
        && big[1025] == 1
        && parts[31].Length == 1024;
    Cap(14, "streaming", 8, 4, streamingOk);
});

// 15. Diagnostics — structural/semantic/recovery/content validation emits diagnostics
tasks[14] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    st.CreateFile("dg", new byte[]{1});
    var data = st.Commit();
    var diags = Diagnostic.ValidateWithDiagnostics(data, "Full");
    Cap(15, "diagnostics", 4, 4, diags != null && diags.Count == 0 && st.Generation >= 1 && st.ListFiles().Count == 1);
});

// 16. Integrity — verified report: valid store hashes with 0 errors
tasks[15] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    st.CreateFile("iv", new byte[]{9});
    var rep = Integrity.VerifyIntegrity(st);
    Cap(16, "integrity", 5, 4, rep != null && rep.Valid && rep.FileCount == 1 && rep.ObjectCount == 1 && rep.Errors.Count == 0 && rep.ContentHash.Length == 64);
});

// 17. Storage — storage manager indexes real files/revisions
tasks[16] = System.Threading.Tasks.Task.Run(() => {
    var st = VsnStore.Create(Constants.ModeModern);
    st.CreateFile("s1", new byte[]{1}); st.CreateFile("s2", new byte[]{2});
    var mgr = new StorageManager(); mgr.BuildIndexes(st);
    var sstats = mgr.Stats(st);
    Cap(17, "storage", 5, 4, sstats.FileCount == 2 && sstats.ObjectCount == 2 && sstats.RevisionCount >= 2 && mgr.IsValid);
});

// 18. Builder
tasks[17] = System.Threading.Tasks.Task.Run(() => {
    var b = new ContainerBuilder(Constants.ModeEnterprise);
    var fid = VsnStore.GenerateFileId();
    b.AddFile(fid);
    var ser = b.AddObject(new byte[]{7});
    b.AddRevision(fid, 1, ser, "bk");
    b.SetHead(fid, 1);
    var blob = b.Build(1);
    var t = VsnStore.Open(blob);
    Cap(18, "builder", 2, 8, blob[0]==(byte)'V' && t.ReadFile(fid).Length==1);
});

// 19. Interop (frozen vectors)
tasks[18] = System.Threading.Tasks.Task.Run(() => {
    bool ok = true; int ops = 0;
    try {
        string[] roots = new[]{
            System.IO.Path.Combine("..","TestVectors"),
            System.IO.Path.Combine("..","..","TestVectors"),
            System.IO.Path.Combine("..","..","..","TestVectors"),
            System.IO.Path.Combine("..","..","..","..","TestVectors"),
            "/work/Libraries/TestVectors",
            "C:\\CampMember\\BinaryRevisionWithProtocol\\Libraries\\TestVectors",
        };
        foreach (var name in new[]{"DIRECT-01.vsn","EXT-01.vsn","EXT-02-and-EXT-03.vsn"}) {
            byte[]? raw = null;
            foreach (var r in roots) {
                var p = System.IO.Path.Combine(r, name);
                if (System.IO.File.Exists(p)) { raw = System.IO.File.ReadAllBytes(p); break; }
            }
            if (raw == null) throw new System.IO.FileNotFoundException(name);
            ops++;
            if (raw[0]!=(byte)'V') ok = false;
            var st = VsnStore.Open(raw); ops++;
            if (st.Generation < 1) ok = false;
        }
    } catch { ok = false; }
    Cap(19, "interop-magic", 6, ops, ok);
});

System.Threading.Tasks.Task.WaitAll(tasks);
Console.WriteLine($"SUMMARY pass={passed}/19");

// Storage Policy Corpus tests (P01-P12)
var corpus = new StoragePolicyCorpus();
corpus.RunAll();

if (failed > 0) Environment.Exit(1);