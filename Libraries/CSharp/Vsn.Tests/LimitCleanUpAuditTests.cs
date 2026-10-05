using Vsn;
using Xunit;

namespace Vsn.Tests;

/// <summary>
/// Audit-phase coverage for the LimitCleanUp library capability in C#.
/// Mirrors the Python audit suite so cross-language semantics are provably
/// identical: limit semantics, per-FileId scope, newest-N rule, return value,
/// zero-limit behaviour, idempotency, monotonicity, FileHead, and recovery.
/// </summary>
public class LimitCleanUpAuditTests
{
    private static byte[] Fid(byte seed) => Enumerable.Repeat(seed, 16).ToArray();

    private static (VsnStore, byte[]) Mk(int n, string path = "a.txt")
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile(path, System.Text.Encoding.ASCII.GetBytes("v1"));
        for (var i = 2; i <= n; i++)
            store.WriteFile(fid, System.Text.Encoding.ASCII.GetBytes($"v{i}"));
        return (store, fid);
    }

    [Theory]
    [InlineData(1, 1, 0)] [InlineData(2, 1, 1)] [InlineData(2, 2, 0)]
    [InlineData(2, 3, 0)] [InlineData(5, 1, 4)] [InlineData(5, 5, 0)]
    [InlineData(5, 6, 0)] [InlineData(10, 5, 5)] [InlineData(10, 1, 9)]
    [InlineData(10, 10, 0)] [InlineData(10, 11, 0)]
    public void LimitBoundaryMatrix(int n, ulong limit, int expectedRemoved)
    {
        var (store, fid) = Mk(n);
        var before = store.ListRevisions(fid);
        var removed = store.LimitCleanUp(fid, limit);
        var after = store.ListRevisions(fid);
        Assert.Equal(expectedRemoved, removed.Count);
        Assert.Equal(Math.Min(n, (int)limit), after.Count);
        // The retained set is always the NEWEST per-file revisions.
        Assert.Equal(before.Skip(before.Count - after.Count), after);
        Assert.Equal(before.Where(r => !after.Contains(r)), removed);
    }

    [Fact]
    public void LimitZeroIsRejectedWithInvalidCanonicalState()
    {
        var (store, fid) = Mk(4);
        TestVectors.AssertThrowsVsn(() => store.LimitCleanUp(fid, 0), 0x000C);
        Assert.Equal(4, store.ListRevisions(fid).Count);
    }

    [Fact]
    public void MonotonicitySmallerThenLargerNeverResurrects()
    {
        var (store, fid) = Mk(10);
        Assert.Equal(7, store.LimitCleanUp(fid, 3).Count);
        Assert.Empty(store.LimitCleanUp(fid, 5));
        Assert.True(store.ListRevisions(fid).SequenceEqual(new ulong[] { 8, 9, 10 }));
        var r = VsnStore.Open(store.Commit());
        Assert.True(r.ListRevisions(fid).SequenceEqual(new ulong[] { 8, 9, 10 }));
        for (ulong gone = 1; gone <= 7; gone++)
            TestVectors.AssertThrowsVsn(() => r.GetRevision(gone), 0x0009);
    }

    [Fact]
    public void MonotonicityLargerThenSmallerReducesRetainedSet()
    {
        var (store, fid) = Mk(10);
        Assert.Equal(new ulong[] { 1, 2, 3, 4, 5 }, store.LimitCleanUp(fid, 5));
        Assert.Equal(new ulong[] { 6, 7 }, store.LimitCleanUp(fid, 3));
        Assert.Equal(new ulong[] { 8, 9, 10 }, store.ListRevisions(fid));
    }

    [Fact]
    public void PerFileIsolationNeverUsesGlobalRevisionNumbering()
    {
        var store = VsnStore.Create();
        var a = store.CreateFile("a.txt", "a1"u8.ToArray());
        var b = store.CreateFile("b.txt", "b1"u8.ToArray());
        for (var i = 2; i <= 5; i++)
        {
            store.WriteFile(a, System.Text.Encoding.ASCII.GetBytes($"a{i}"));
            store.WriteFile(b, System.Text.Encoding.ASCII.GetBytes($"b{i}"));
        }
        // a owns odd ids, b owns even ids.
        Assert.Equal(new ulong[] { 1, 3, 5, 7, 9 }, store.ListRevisions(a));
        Assert.Equal(new ulong[] { 2, 4, 6, 8, 10 }, store.ListRevisions(b));

        Assert.Equal(new ulong[] { 1, 3 }, store.LimitCleanUp(a, 3));
        Assert.True(store.ListRevisions(a).SequenceEqual(new ulong[] { 5, 7, 9 }));
        Assert.True(store.ListRevisions(b).SequenceEqual(new ulong[] { 2, 4, 6, 8, 10 }),
                    "File B must be completely untouched");

        var r = VsnStore.Open(store.Commit());
        Assert.True(r.ListRevisions(b).SequenceEqual(new ulong[] { 2, 4, 6, 8, 10 }));
        Assert.Equal("b5"u8.ToArray(), r.ReadFile(b));
    }

    [Fact]
    public void FileHeadIsNewestRetainedAndNeverDangling()
    {
        var (store, fid) = Mk(8);
        store.LimitCleanUp(fid, 5);
        var retained = store.ListRevisions(fid);
        Assert.Equal(new ulong[] { 4, 5, 6, 7, 8 }, retained);
        Assert.Equal(retained[^1], store.GetCurrentRevision(fid));

        var data = store.Commit();
        foreach (var rec in ContainerParser.Parse(data).Records)
        {
            if (rec.RType == Constants.RecFileHead)
                Assert.Contains(rec.GetField(Constants.FidHeadRevId)!.AsUvarint(),
                                retained);
            if (rec.RType == Constants.RecRevision)
                Assert.Contains(rec.GetField(Constants.FidRevId)!.AsUvarint(),
                                retained);
        }
    }

    [Fact]
    public void SingleRetainedRevisionIsHeadAndReadable()
    {
        var (store, fid) = Mk(6);
        Assert.Equal(new ulong[] { 1, 2, 3, 4, 5 }, store.LimitCleanUp(fid, 1));
        var r = VsnStore.Open(store.Commit());
        Assert.Equal(new ulong[] { 6 }, r.ListRevisions(fid));
        Assert.Equal(6UL, r.GetCurrentRevision(fid));
        Assert.Equal("v6"u8.ToArray(), r.ReadFile(fid));
    }

    [Fact]
    public void DeletedRevisionsAreUnavailableThroughEveryRevisionApi()
    {
        var (store, fid) = Mk(6);
        store.LimitCleanUp(fid, 5);
        var r = VsnStore.Open(store.Commit());
        TestVectors.AssertThrowsVsn(() => r.GetRevision(1), 0x0009);
        TestVectors.AssertThrowsVsn(() => r.CheckoutRevision(fid, 1), 0x0009);
        TestVectors.AssertThrowsVsn(() => r.RestoreRevision(fid, 1), 0x0009);
        // GetObjectSerial reports absence by returning null, exactly as for an
        // unknown revision, and never returns the stale ObjectSerial.
        Assert.Null(r.GetObjectSerial(fid, 1));
        Assert.Equal(r.GetObjectSerial(fid, 1), r.GetObjectSerial(fid, 9999));
    }

    [Fact]
    public void RevisionDeletionIsNotObjectGarbageCollection()
    {
        var (store, fid) = Mk(6);
        var objects = store.ListObjects();
        var oldSerial = store.GetRevision(1).ObjectSerial!.Value;
        var oldContent = store.Materialize(oldSerial);
        store.LimitCleanUp(fid, 5);
        var r = VsnStore.Open(store.Commit());
        // Revision gone ...
        TestVectors.AssertThrowsVsn(() => r.GetRevision(1), 0x0009);
        // ... object deliberately NOT reclaimed.
        Assert.Equal(oldContent, r.Materialize(oldSerial));
        Assert.Equal(objects, r.ListObjects());
    }

    [Fact]
    public void NewCommitAfterCleanupDoesNotResurrectHistory()
    {
        var (store, fid) = Mk(8);
        store.LimitCleanUp(fid, 5);
        Assert.Equal(new ulong[] { 4, 5, 6, 7, 8 }, store.ListRevisions(fid));
        store.Commit();
        store.WriteFile(fid, "v9"u8.ToArray());
        Assert.Equal(new ulong[] { 4, 5, 6, 7, 8, 9 }, store.ListRevisions(fid));
        Assert.Equal(new ulong[] { 4 }, store.LimitCleanUp(fid, 5));
        var data = store.Commit();
        var r = VsnStore.Open(data);
        Assert.Equal(new ulong[] { 5, 6, 7, 8, 9 }, r.ListRevisions(fid));
        Assert.Equal(9UL, r.GetCurrentRevision(fid));
        Assert.True(Recovery.Recover(data).Recovered);
    }

    [Fact]
    public void RecoveryWorksFromCanonicalStateAlone()
    {
        var (store, fid) = Mk(6);
        store.LimitCleanUp(fid, 5);
        var data = store.Commit();
        var rec = Recovery.Recover(data);
        Assert.True(rec.Recovered);
        Assert.Equal(store.Generation, rec.AcceptedGeneration);
        Assert.True(VsnStore.Open(data).ListRevisions(fid)
            .SequenceEqual(new ulong[] { 2, 3, 4, 5, 6 }));
    }

    [Fact]
    public void FullValidationPassesAfterCleanup()
    {
        var (store, fid) = Mk(6);
        store.LimitCleanUp(fid, 2);
        var data = store.Commit();
        Validate.Structural(data);
        Validate.Semantic(data);
        Validate.Content(data);
        Validate.Run(data, "Full");
    }

    [Fact]
    public void UnknownFileIdIsRejected()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "v1"u8.ToArray());
        TestVectors.AssertThrowsVsn(() => store.LimitCleanUp(Fid(0xEE), 5), 0x0009);
    }
}