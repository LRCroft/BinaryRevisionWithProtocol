using Vsn;
using Xunit;

namespace Vsn.Tests;

public class IntegrityStorageTests
{
    [Fact]
    public void LibraryLevelIntegrityVerificationUsesCanonicalState()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "integrity"u8.ToArray());
        store.Commit();
        var report = Integrity.VerifyIntegrity(store);
        Assert.True(report.Valid);
        Assert.Equal(1, report.FileCount);
        Assert.Equal(1, report.ObjectCount);
        Assert.Equal(1, report.RevisionCount);
        Assert.Equal(Integrity.CanonicalHash(store.CanonicalData), report.ContentHash);
        Assert.Empty(report.Errors);
    }

    [Fact]
    public void DerivedIndexCacheBuildRebuildGcStatsCleanup()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "aaa"u8.ToArray());
        store.CreateFile("b.txt", "bbbb"u8.ToArray());
        store.Commit();
        var sm = new StorageManager();
        sm.BuildIndexes(store);
        Assert.True(sm.IsValid);
        Assert.Equal(16, sm.LookupFile("a.txt")!.Length);
        sm.CachePut(1, "cached"u8.ToArray());
        Assert.Equal(1, sm.CacheCount);
        var stats = sm.Stats(store);
        Assert.Equal(2, stats.FileCount);
        Assert.Equal(2, stats.ObjectCount);
        Assert.True(stats.IndexEntries >= 2);
        Assert.Equal(1, sm.Gc());
        Assert.Equal(0, sm.CacheCount);
        sm.Invalidate();
        Assert.False(sm.IsValid);
        sm.Rebuild(store);
        Assert.True(sm.IsValid);
    }

    [Fact]
    public void RecoveryRemainsFunctionalAfterAllDerivedDataDeleted()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "survives"u8.ToArray());
        store.WriteFile(fid, "survives!"u8.ToArray());
        var data = store.Commit();
        var sm = new StorageManager();
        sm.BuildIndexes(store);
        sm.CachePut(1, "derived"u8.ToArray());
        // Delete every derived structure.
        sm.Invalidate();
        Assert.False(sm.IsValid);
        Assert.Equal(0, sm.CacheCount);
        // Recovery and reads must still work from canonical bytes alone.
        var rr = Recovery.Recover(data);
        Assert.Equal("RECOVERED", rr.Status);
        Assert.Equal(1ul, rr.AcceptedGeneration);
        var re = VsnStore.Open(data);
        Assert.Equal("survives!"u8.ToArray(), re.ReadFile(fid));
        Assert.Single(re.ListFiles());
    }

    [Fact]
    public void RecoveryWithoutIndexesCachesCheckpointsOrPrivateDatabases()
    {
        var data = TestVectors.Load("EXT-02-and-EXT-03");
        var rr = Recovery.Recover(data);
        Assert.True(rr.Recovered);
        Assert.Equal(1ul, rr.AcceptedGeneration);
        Assert.Equal("hello vsn\n!!"u8.ToArray(), VsnContainer.Open(data).Materialize(20));
    }

    [Fact]
    public void MalformedContainerHandlingAcrossLevels()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "x"u8.ToArray());
        var good = store.Commit();
        Assert.Throws<VsnException>(() => VsnStore.Open(good[..10]));
        Assert.Equal("TRUNCATED", Recovery.Recover(good[..10]).Status);
        var corrupt = (byte[])good.Clone();
        corrupt[4] = 0x09; // break container format version
        Assert.Equal("MALFORMED", Recovery.Recover(corrupt).Status);
        Assert.Equal(0x0003, Diagnostic.ValidateWithDiagnostics(corrupt, "Structural")[0].Code);
    }
}
