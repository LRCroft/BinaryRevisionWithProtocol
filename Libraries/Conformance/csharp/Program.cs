using System.Text;
using Vsn;

// Executable LimitCleanUp probe for the C# library.
//
// This does NOT merely check that a method named LimitCleanUp exists. It performs
// a real 10-revision history, runs the operation, and verifies the resulting
// revision history, the retained identities, recovery, and argument rejection.
//
// Prints a machine-readable final line:
//    LIMIT_CLEANUP <PASS|FAIL> removed=<csv> retained=<csv>

var failures = new List<string>();
void Check(bool cond, string label) { if (!cond) failures.Add(label); }

(VsnStore Store, byte[] Fid) Build(int n, string path = "a.txt")
{
    var store = VsnStore.Create();
    var fid = store.CreateFile(path, Encoding.ASCII.GetBytes("v1"));
    for (var i = 2; i <= n; i++)
        store.WriteFile(fid, Encoding.ASCII.GetBytes($"v{i}"));
    return (store, fid);
}

static bool Same(IEnumerable<ulong> a, params ulong[] b) => a.SequenceEqual(b);

// --- 1-8: real container, 10 revisions, LimitCleanUp(file, 5) ---------------
var (store, fid) = Build(10);
var before = store.ListRevisions(fid)
    .ToDictionary(r => r, r => store.GetRevision(r).ObjectSerial);
var removed = store.LimitCleanUp(fid, 5);
var retained = store.ListRevisions(fid);
Check(removed.Count == 5, $"exactly 5 removed, got {removed.Count}");
Check(retained.Count == 5, $"exactly 5 retained, got {retained.Count}");
Check(removed.SequenceEqual(new ulong[] { 1, 2, 3, 4, 5 }),
      $"removed ids, got [{string.Join(",", removed)}]");
Check(Same(retained, 6, 7, 8, 9, 10),
      $"retained ids, got [{string.Join(",", retained)}]");

// 6: ObjectSerials of retained revisions
foreach (var r in retained)
    Check(store.GetRevision(r).ObjectSerial == before[r],
          $"retained ObjectSerial {r} unchanged");

// 7: deleted revisions are inaccessible
try { store.GetRevision(1); Check(false, "deleted revision 1 still accessible"); }
catch (VsnException e) { Check(e.Code == 0x0009, $"deleted raises 0x0009, got 0x{e.Code:X4}"); }

// 8: FileHead
var head = store.GetCurrentRevision(fid);
Check(head == retained[^1] && head == 10, $"FileHead is newest retained, got {head}");

// 9: close / reopen
var data = store.Commit();
var reopened = VsnStore.Open(data);
Check(Same(reopened.ListRevisions(fid), 6, 7, 8, 9, 10), "reopen lists retained set");
Check(reopened.GetCurrentRevision(fid) == 10, "reopened FileHead");
foreach (var gone in new ulong[] { 1, 2, 3, 4, 5 })
{
    try { reopened.GetRevision(gone); Check(false, $"deleted {gone} accessible after reopen"); }
    catch (VsnException) { /* expected */ }
}

// 10: recovery
var rec = Recovery.Recover(data);
Check(rec.Recovered, "recovery succeeded");
Check(rec.AcceptedGeneration == store.Generation, "recovery generation matches");

// 11-12: idempotency, three calls
for (var i = 0; i < 3; i++)
    Check(reopened.LimitCleanUp(fid, 5).Count == 0, $"repeat call {i + 1} removes nothing");
Check(Same(reopened.ListRevisions(fid), 6, 7, 8, 9, 10), "retained set stable");
Check(Recovery.Recover(reopened.Commit()).Recovered, "recovery after repeated cleanup");

// 13: limit greater than history
var (fresh, ffid) = Build(3);
Check(fresh.LimitCleanUp(ffid, 99).Count == 0, "limit > history removes nothing");
Check(fresh.ListRevisions(ffid).Count == 3, "limit > history keeps all");

// 14: limit 0 rejected
try { reopened.LimitCleanUp(fid, 0); Check(false, "limit 0 was not rejected"); }
catch (VsnException e) { Check(e.Code == 0x000C, $"limit 0 rejected 0x000C, got 0x{e.Code:X4}"); }
Check(Same(reopened.ListRevisions(fid), 6, 7, 8, 9, 10), "history unchanged after reject");

// 15: an unrelated file must not be changed
var (two, fa) = Build(6);
var fb = two.CreateFile("b.txt", Encoding.ASCII.GetBytes("b1"));
for (var i = 2; i <= 5; i++) two.WriteFile(fb, Encoding.ASCII.GetBytes($"b{i}"));
var bBefore = two.ListRevisions(fb);
var bContent = two.ReadFile(fb);
two.LimitCleanUp(fa, 2);
Check(two.ListRevisions(fb).SequenceEqual(bBefore), "unrelated file revisions unchanged");
Check(bContent.SequenceEqual(two.ReadFile(fb)), "unrelated file content unchanged");

var status = failures.Count == 0 ? "PASS" : "FAIL";
Console.WriteLine($"LIMIT_CLEANUP {status} removed={string.Join(",", removed)} " +
                  $"retained={string.Join(",", retained)}");
foreach (var f in failures) Console.WriteLine("  FAIL: " + f);
return failures.Count == 0 ? 0 : 1;