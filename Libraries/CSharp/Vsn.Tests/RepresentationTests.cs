using Vsn;
using Xunit;

namespace Vsn.Tests;

public class RepresentationTests
{
    private static byte[] Fill(byte b, int n = 16)
    {
        var a = new byte[n];
        Array.Fill(a, b);
        return a;
    }

    [Fact]
    public void Direct1RoundTripsThroughBuiltContainer()
    {
        var fid = Fill(0x11);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        ulong serial = b.AddObject("direct!"u8.ToArray());
        b.AddRevision(fid, 1, serial, "a.txt");
        b.SetHead(fid, 1);
        var c = VsnContainer.Open(b.Build(1));
        Assert.Equal("direct!"u8.ToArray(), c.Materialize(serial));
        Assert.Equal(Constants.ModeModern, c.Mode);
    }

    [Fact]
    public void Extents1LiteralOperation()
    {
        var fid = Fill(0x22);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        ulong serial = b.AddObjectRaw(Writer.Extents1Descriptor(new() { Writer.LiteralOperation("alpha"u8.ToArray()) }));
        b.AddRevision(fid, 1, serial, "a.txt");
        b.SetHead(fid, 1);
        Assert.Equal("alpha"u8.ToArray(), VsnContainer.Open(b.Build(1)).Materialize(serial));
    }

    [Fact]
    public void Extents1CopyPlusLiteralDependency()
    {
        var fid = Fill(0x33);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        ulong src = b.AddObject("hello vsn\n"u8.ToArray());
        ulong dst = b.AddObjectRaw(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(src, 0, 10), Writer.LiteralOperation("!!"u8.ToArray()),
        }));
        b.AddRevision(fid, 1, src, "a.txt");
        b.AddRevision(fid, 2, dst, "b.txt");
        b.SetHead(fid, 2);
        var c = VsnContainer.Open(b.Build(2));
        Assert.Equal("hello vsn\n"u8.ToArray(), c.Materialize(src));
        Assert.Equal("hello vsn\n!!"u8.ToArray(), c.Materialize(dst));
    }
}

public class DependencyTests
{
    private static byte[] Fill(byte b, int n = 16)
    {
        var a = new byte[n];
        Array.Fill(a, b);
        return a;
    }

    [Fact]
    public void DependencyValidationRejectsMissingObjectSerial()
    {
        var fid = Fill(0x44);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        b.AddRevision(fid, 1, 999, "a.txt"); // no such object
        b.SetHead(fid, 1);
        TestVectors.AssertThrowsVsn(() => Validate.Run(b.Build(1), "Semantic"), 0x0008);
    }

    [Fact]
    public void DependencyCycleRejectedDuringMaterialization()
    {
        var fid = Fill(0x55);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        b.AddObjectRaw(Writer.Extents1Descriptor(new() { Writer.CopyOperation(2, 0, 1) }), 1);
        b.AddObjectRaw(Writer.Extents1Descriptor(new() { Writer.CopyOperation(1, 0, 1) }), 2);
        b.AddRevision(fid, 1, 1, "a.txt");
        b.SetHead(fid, 1);
        var c = VsnContainer.Open(b.Build(1));
        TestVectors.AssertThrowsVsn(() => c.Materialize(1), 0x000C);
    }

    [Fact]
    public void Extents1CopyRangeOutOfBoundsRejected()
    {
        var fid = Fill(0x56);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        ulong src = b.AddObject("abc"u8.ToArray());
        ulong dst = b.AddObjectRaw(Writer.Extents1Descriptor(new() { Writer.CopyOperation(src, 0, 99) }));
        b.AddRevision(fid, 1, dst, "a.txt");
        b.SetHead(fid, 1);
        var c = VsnContainer.Open(b.Build(1));
        TestVectors.AssertThrowsVsn(() => c.Materialize(dst), 0x000C);
    }
}
