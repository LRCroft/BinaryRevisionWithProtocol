using Vsn;
using Xunit;

namespace Vsn.Tests;

public class DiffMergeTests
{
    [Fact]
    public void ObjectDiff()
    {
        var left = VsnStore.Create();
        left.CreateFile("a.txt", "a"u8.ToArray());
        var right = VsnStore.Create();
        right.CreateFile("a.txt", "a"u8.ToArray());
        right.CreateFile("b.txt", "b"u8.ToArray());
        var d = Diff.DiffObjects(left.ListObjects(), right.ListObjects());
        Assert.Single(d.Shared);
        Assert.Single(d.Added);
        Assert.Empty(d.Removed);
    }

    [Fact]
    public void FileDiffAndRevisionDiff()
    {
        var left = VsnStore.Create();
        left.CreateFile("a.txt", "one"u8.ToArray());
        left.CreateFile("gone.txt", "bye"u8.ToArray());
        var right = VsnStore.Create();
        right.CreateFile("a.txt", "two"u8.ToArray());
        right.CreateFile("new.txt", "hi"u8.ToArray());
        var d = Diff.DiffFiles(left, right);
        Assert.Equal(new[] { "a.txt" }, d.Modified);
        Assert.Equal(new[] { "gone.txt" }, d.Deleted);
        Assert.Equal(new[] { "new.txt" }, d.Added);

        var store = VsnStore.Create();
        var fid = store.CreateFile("r.txt", "v1"u8.ToArray());
        store.WriteFile(fid, "v2-longer"u8.ToArray());
        var rd = Diff.DiffRevisions(store, fid, 1, 2);
        Assert.True(rd.Changed);
        Assert.Equal(9 - 2, rd.AddedBytes);
    }

    private static (VsnStore baseStore, VsnStore ours, VsnStore theirs) ConflictStores()
    {
        var b = VsnStore.Create();
        b.CreateFile("a.txt", "base"u8.ToArray());
        var o = VsnStore.Create();
        o.CreateFile("a.txt", "ours"u8.ToArray());
        var t = VsnStore.Create();
        t.CreateFile("a.txt", "theirs"u8.ToArray());
        return (b, o, t);
    }

    [Fact]
    public void ThreeWayMergeAutoMergesNonConflictingChanges()
    {
        var b = VsnStore.Create();
        b.CreateFile("a.txt", "base"u8.ToArray());
        b.CreateFile("b.txt", "base"u8.ToArray());
        var o = VsnStore.Create();
        o.CreateFile("a.txt", "ours"u8.ToArray());
        o.CreateFile("b.txt", "base"u8.ToArray());
        var t = VsnStore.Create();
        t.CreateFile("a.txt", "base"u8.ToArray());
        t.CreateFile("b.txt", "theirs"u8.ToArray());
        var m = Merge.ThreeWayMerge(b, o, t);
        Assert.False(m.HasConflicts);
        Assert.Equal("ours"u8.ToArray(), m.MergedFiles["a.txt"]);
        Assert.Equal("theirs"u8.ToArray(), m.MergedFiles["b.txt"]);
    }

    [Fact]
    public void ThreeWayMergeReportsConflictsWithoutSilentDataLoss()
    {
        var (b, o, t) = ConflictStores();
        var m = Merge.ThreeWayMerge(b, o, t);
        Assert.True(m.HasConflicts);
        Assert.Single(m.Conflicts);
        Assert.Equal("a.txt", m.Conflicts[0].Path);
        Assert.Equal("ours"u8.ToArray(), m.Conflicts[0].OursContent);
        Assert.Equal("theirs"u8.ToArray(), m.Conflicts[0].TheirsContent);
    }

    [Fact]
    public void ExplicitConflictResolution()
    {
        var (b, o, t) = ConflictStores();
        var m = Merge.ThreeWayMerge(b, o, t);
        Merge.ResolveConflict(m, "a.txt", "resolved"u8.ToArray());
        Assert.False(m.HasConflicts);
        Assert.Equal("resolved"u8.ToArray(), m.MergedFiles["a.txt"]);
    }
}
