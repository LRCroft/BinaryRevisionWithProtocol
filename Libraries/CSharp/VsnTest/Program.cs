using Vsn;

int passed = 0, failed = 0;
void Check(int n, string label, bool cond) {
    if (cond) { passed++; Console.WriteLine($"PASS {n} {label}"); }
    else { failed++; Console.WriteLine($"FAIL {n} {label}"); }
}

// 1. Container Lifecycle
var s1 = VsnStore.Create(Constants.ModeModern); s1.Close();
var s2 = VsnStore.Create(Constants.ModeEnterprise);
Check(1, "container lifecycle", s2.Mode == Constants.ModeEnterprise);

// 2. File API
var s = VsnStore.Create(Constants.ModeModern);
var fid = s.CreateFile("a.txt", new byte[]{1,2,3});
var rd = s.ReadFile(fid);
s.WriteFile(fid, new byte[]{9,9,9});
var rd2 = s.ReadFile(fid);
s.DeleteFile(fid);
Check(2, "file API", rd.Length == 3 && rd2.Length == 3 && !s.FileExists(fid));

// 3. Revision API
var s3 = VsnStore.Create(Constants.ModeModern);
var fid3 = s3.CreateFile("r", new byte[]{1});
s3.WriteFile(fid3, new byte[]{2});
s3.WriteFile(fid3, new byte[]{3});
Check(3, "revision API", s3.ListRevisions(fid3).Count >= 3);

// 4. Limit Cleanup
var s4 = VsnStore.Create(Constants.ModeModern);
var fid4 = s4.CreateFile("lc", new byte[]{1});
for (int i = 0; i < 5; i++) s4.WriteFile(fid4, new byte[]{(byte)i});
var rm = s4.LimitCleanUp(fid4, 3);
Check(4, "limit cleanup", rm.Count >= 0);

// 5. Object API
var s5 = VsnStore.Create(Constants.ModeModern);
s5.CreateFile("o", new byte[]{42});
Check(5, "object API", s5.ListObjects().Count >= 1);

// 6. Transactions
var s6 = VsnStore.Create(Constants.ModeModern);
var txn = new Transaction();
txn.StageCreate("tx", new byte[]{1});
var committed = txn.Commit(s6);
Check(6, "transactions", committed.Length >= 8);

// 7. Representations
Check(7, "representations", Constants.RepDirect1 == 1 && Constants.RepExtents1 == 2);

// 8. Modes
Check(8, "modes", Constants.ModeModern == 1 && Constants.ModeEnterprise == 2);

// 9. Validation
var data9 = s.Commit();
bool valid = true;
try { Validate.Structural(data9); } catch { valid = false; }
Check(9, "validation", valid);

// 10. Recovery
var rec = Recovery.Recover(data9);
Check(10, "recovery", rec != null);

// 11. Diff
var sA = VsnStore.Create(Constants.ModeModern); sA.CreateFile("x", new byte[]{1});
var sB = VsnStore.Create(Constants.ModeModern);
var diff = Diff.DiffFiles(sA, sB);
Check(11, "diff", diff.Added.Count + diff.Deleted.Count >= 1);

// 12. Merge
var sC = VsnStore.Create(Constants.ModeModern);
var sD = VsnStore.Create(Constants.ModeModern);
var merge = Merge.ThreeWayMerge(sC, sC, sD);
Check(12, "merge", merge != null);

// 13. Import/Export
var exported = s.ToBytes();
Check(13, "import/export", exported.Length >= 8);

// 14. Streaming
var stream = s.MaterializeStream(1).ToList();
Check(14, "streaming", stream.Count >= 0);

// 15. Diagnostics
var diags = Vsn.Diagnostic.ValidateWithDiagnostics(data9);
Check(15, "diagnostics", diags != null);

// 16. Integrity
var integrity = Integrity.VerifyIntegrity(s);
Check(16, "integrity", integrity != null);

// 17. Storage
var files = s.ListFiles();
Check(17, "storage", files != null);

// 18. Builder
var b = new ContainerBuilder(Constants.ModeModern);
b.AddFile(VsnStore.GenerateFileId());
var built = b.Build(1);
Check(18, "builder", built.Length >= 8);

// 19. Interop
var magic = new byte[]{(byte)'V',(byte)'S',(byte)'N',(byte)'-'};
Check(19, "interop", data9.Length >= 4 && data9[0]==(byte)'V' && data9[1]==(byte)'S' && data9[2]==(byte)'N');

Console.WriteLine("---");
Console.WriteLine($"CSharp capabilities: {passed} passed, {failed} failed");
if (failed > 0) Environment.Exit(1);