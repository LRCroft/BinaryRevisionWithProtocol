// Independent C# consumer: a separate project referencing Vsn.csproj that uses ONLY the public API.
using System;
using System.Linq;
using Vsn;

class Program
{
    static int fails = 0;
    static void Check(bool c, string m)
    {
        if (c) Console.WriteLine("ok  - " + m);
        else { Console.WriteLine("FAIL: " + m); fails++; }
    }

    static void Main()
    {
        var s = VsnStore.Create(Constants.ModeModern);
        Check(s != null, "VsnStore.Create");
        byte[] payload = "CS-CONSUMER"u8.ToArray();
        var fid = s.CreateFile("cs.txt", payload);
        Check(s.FileExists(fid), "createFile + fileExists");
        var read = s.ReadFile(fid);
        Check(read.SequenceEqual(payload), "readFile round-trips");
        s.WriteFile(fid, "CS-CONSUMER-2"u8.ToArray());
        Check(s.ListRevisions(fid).Count >= 1, "revision tracked");
        var data = s.Commit();
        Check(data != null && data.Length > 0, "commit produced canonical bytes");
        Check(Diagnostic.ValidateWithDiagnostics(data, "Full").Count == 0, "Full validation is clean");
        var rec = Recovery.Recover(data);
        Check(rec != null, "recover returns a result");
        Check(VsnStore.Create(StoragePolicy.HIGHLY_HORIZONTAL) != null, "Create(StoragePolicy) constructs a store");

        // Storage Policy wire-in: public create-with-policy -> ToBytes -> public Parse -> policy read back.
        Check((int)StoragePolicy.HIGHLY_VERTICAL == 1 && (int)StoragePolicy.VERTICAL == 2
            && (int)StoragePolicy.HORIZONTAL == 3 && (int)StoragePolicy.HIGHLY_HORIZONTAL == 4,
            "4 canonical policy values 1..4");
        int[] expected = { 1, 2, 3, 4 };
        StoragePolicy[] policies = { StoragePolicy.HIGHLY_VERTICAL, StoragePolicy.VERTICAL,
                                     StoragePolicy.HORIZONTAL, StoragePolicy.HIGHLY_HORIZONTAL };
        bool allRoundTrip = true;
        for (int i = 0; i < policies.Length; i++)
        {
            var sp = VsnStore.Create(policies[i]);
            var f = sp.CreateFile("fs.txt", System.Text.Encoding.UTF8.GetBytes("POL" + i));
            var bytes = sp.ToBytes();
            var parsed = ContainerParser.Parse(bytes);
            if (!parsed.StoragePolicy.HasValue || parsed.StoragePolicy.Value != expected[i]) { allRoundTrip = false; break; }
        }
        Check(allRoundTrip, "SP wire-in: all 4 policies round-trip through public Parse");
        var b1 = VsnStore.Create(StoragePolicy.HORIZONTAL).ToBytes();
        var b2 = VsnStore.Create(StoragePolicy.HIGHLY_VERTICAL).ToBytes();
        Check(b1.Length > 0 && b2.Length > 0 && !b1.SequenceEqual(b2), "distinct policies -> distinct wire bytes");

        if (fails == 0) Console.WriteLine("CONSUMER C# PASS");
        else { Console.WriteLine("CONSUMER C# FAIL (" + fails + ")"); Environment.Exit(1); }
    }
}