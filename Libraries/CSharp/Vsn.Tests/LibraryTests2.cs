using Vsn;
using Xunit;

namespace Vsn.Tests;

public class RevisionApiTests
{
    [Fact]
    public void RevisionListRetrieveCheckoutRestoreCompare()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "v1"u8.ToArray());
        store.WriteFile(fid, "v2"u8.ToArray());
        store.WriteFile(fid, "v3"u8.ToArray());
        Assert.Equal(new ulong[] { 1, 2, 3 }, store.ListRevisions(fid));
        Assert.Equal(3ul, store.GetCurrentRevision(fid));
        Assert.Equal(Constants.Present, store.GetRevision(1).Presence);
        Assert.Equal("v1"u8.ToArray(), store.CheckoutRevision(fid, 1));
        Assert.True(store.CompareRevisions(fid, 1, 3));
        Assert.False(store.CompareRevisions(fid, 2, 2));
        store.RestoreRevision(fid, 1);
        Assert.Equal("v1"u8.ToArray(), store.ReadFile(fid));
        Assert.Equal(fid, store.GetRevision(3).FileId);
    }

    [Fact]
    public void CheckoutRejectsRevisionIdFromDifferentFile()
    {
        var store = VsnStore.Create();
        var a = store.CreateFile("a.txt", "a"u8.ToArray());
        store.CreateFile("b.txt", "b"u8.ToArray());
        TestVectors.AssertThrowsVsn(() => store.CheckoutRevision(a, 2), 0x000B);
    }
}

public class ObjectApiTests
{
    [Fact]
    public void ObjectEnumerateInspectSerialMaterializeMetadata()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("a.txt", "payload"u8.ToArray());
        Assert.Equal(new ulong[] { 1 }, store.ListObjects());
        ulong serial = store.GetObjectSerial(fid)!.Value;
        Assert.Equal(1ul, serial);
        var info = store.GetObjectInfo(serial);
        Assert.Equal(Constants.RepDirect1, info.RepresentationIdentity);
        Assert.Equal(1, info.RepresentationVersion);
        Assert.Equal(7, info.Length);
        Assert.Equal("payload"u8.ToArray(), store.Materialize(serial));
        Assert.Equal(serial, store.GetObjectInfo(serial).Serial);
    }

    [Fact]
    public void Extents1ObjectMaterializesThroughCopyPlusLiteral()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("base.txt", "hello vsn\n"u8.ToArray());
        ulong src = store.GetObjectSerial(fid)!.Value;
        ulong dst = store.AddObjectDescriptor(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(src, 0, 10), Writer.LiteralOperation("!!"u8.ToArray()),
        }));
        store.WriteFile(fid, store.Materialize(dst));
        Assert.Equal("hello vsn\n!!"u8.ToArray(), store.ReadFile(fid));
        Assert.Equal(Constants.RepExtents1, store.GetObjectInfo(dst).RepresentationIdentity);
    }
}

