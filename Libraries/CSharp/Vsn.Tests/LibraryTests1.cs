using Vsn;
using Xunit;

namespace Vsn.Tests;

public class ContainerLifecycleTests
{
    [Fact]
    public void CreateOpenCloseReopen()
    {
        var store = VsnStore.Create();
        Assert.Equal(Constants.ModeModern, store.Mode);
        var fid = store.CreateFile("a.txt", "hello"u8.ToArray());
        var data = store.Commit();
        store.Close();
        Assert.True(store.IsClosed);
        Assert.Throws<VsnException>(() => store.ListFiles());

        var reopened = VsnStore.Open(data);
        Assert.Equal("hello"u8.ToArray(), reopened.ReadFile(fid));
        reopened.Reopen();
        Assert.Equal("hello"u8.ToArray(), reopened.ReadFile(fid));
    }

    [Fact]
    public void InspectReportsContainerMetadata()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "x"u8.ToArray());
        store.CreateFile("b.txt", "y"u8.ToArray());
        var info = store.Inspect();
        Assert.Equal(2, info.FileCount);
        Assert.Equal(2, info.ObjectCount);
        Assert.Equal(2, info.RevisionCount);
    }

    [Fact]
    public void ValidateExposesAllLevels()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "data"u8.ToArray());
        var data = store.Commit();
        foreach (var level in new[] { "Structural", "Semantic", "Recovery", "Content", "Full" })
            Validate.Run(data, level);
        Assert.Empty(Diagnostic.ValidateWithDiagnostics(data, "Full"));
        TestVectors.AssertThrowsVsn(() => Validate.Run(data[..8], "Structural"), 0x0002);
        Assert.Single(Diagnostic.ValidateWithDiagnostics(data[..8], "Full"));
    }
}

public class FileApiTests
{
    [Fact]
    public void FileCreateReadWriteDeleteRename()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "one"u8.ToArray());
        Assert.Equal("one"u8.ToArray(), store.ReadFile(fid));
        store.WriteFile(fid, "two"u8.ToArray());
        Assert.Equal("two"u8.ToArray(), store.ReadFile(fid));
        store.RenameFile(fid, "b.txt");
        Assert.Equal(fid, store.GetFileId("b.txt"));
        Assert.Equal("two"u8.ToArray(), store.ReadFile(fid));
        store.DeleteFile(fid);
        Assert.False(store.FileExists(fid));
        Assert.Throws<VsnException>(() => store.ReadFile(fid));
    }

    [Fact]
    public void MultipleFilesCoexistAndEnumerate()
    {
        var store = VsnStore.Create();
        var a = store.CreateFile("a.txt", "A"u8.ToArray());
        var b = store.CreateFile("b.txt", "B"u8.ToArray());
        var c = store.CreateFile("c.txt", "C"u8.ToArray());
        var paths = store.ListFiles().Select(f => f.Path).OrderBy(p => p);
        Assert.Equal(new[] { "a.txt", "b.txt", "c.txt" }, paths);
        var data = store.Commit();
        var re = VsnStore.Open(data);
        Assert.Equal("A"u8.ToArray(), re.ReadFile(a));
        Assert.Equal("B"u8.ToArray(), re.ReadFile(b));
        Assert.Equal("C"u8.ToArray(), re.ReadFile(c));
    }

    [Fact]
    public void FileIdIs16OpaqueBytesAndStableAcrossCommitReopen()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "x"u8.ToArray());
        Assert.Equal(16, fid.Length);
        var data = store.Commit();
        var re = VsnStore.Open(data);
        Assert.Equal(fid, re.GetFileId("a.txt"));
        var meta = re.GetFileMetadata(fid);
        Assert.Equal("a.txt", meta.Path);
        Assert.Equal(1ul, meta.HeadRevision);
    }

    [Fact]
    public void DuplicatePathRejected()
    {
        var store = VsnStore.Create();
        store.CreateFile("dup.txt", "1"u8.ToArray());
        TestVectors.AssertThrowsVsn(() => store.CreateFile("dup.txt", "2"u8.ToArray()), 0x000A);
    }

    /// <summary>
    /// Content validation must REJECT a dependency cycle: Structural and Semantic
    /// levels both pass it, so only Content level materialization can catch it.
    /// This proves the Content level is load-bearing rather than a no-op.
    /// </summary>
    [Fact]
    public void ContentValidationRejectsDependencyCycle()
    {
        // Object 1 COPYs from object 2; object 2 COPYs from object 1 -> cycle.
        var one = Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(2, 0, 4),
        });
        var two = Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(1, 0, 4),
        });

        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddObjectRaw(one, 1);
        b.AddObjectRaw(two, 2);
        var data = b.Build(1);

        // Structural framing is intact and semantic references resolve ...
        Validate.Structural(data);
        Validate.Semantic(data);
        // ... but Content materialization must fail on the cycle.
        TestVectors.AssertThrowsVsn(() => Validate.Content(data), 0x000C);
        TestVectors.AssertThrowsVsn(() => Validate.Run(data, "Full"), 0x000C);

        var diags = Diagnostic.ValidateWithDiagnostics(data, "Full");
        Assert.Single(diags);
        Assert.Equal(Severity.Error, diags[0].Severity);
        Assert.Equal("Content", diags[0].Operation);
    }

    /// <summary>Content validation rejects a COPY from a missing ObjectSerial.</summary>
    [Fact]
    public void ContentValidationRejectsMissingDependency()
    {
        var dangling = Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(99, 0, 4),
        });
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddObjectRaw(dangling, 1);
        var data = b.Build(1);
        TestVectors.AssertThrowsVsn(() => Validate.Content(data), 0x0008);
    }
}

