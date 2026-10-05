using Vsn;
using Xunit;

namespace Vsn.Tests;

public class ModeTests
{
    private static byte[] Fill(byte b, int n = 16)
    {
        var a = new byte[n];
        Array.Fill(a, b);
        return a;
    }

    [Fact]
    public void UnsupportedRepresentationIdentityRejected()
    {
        var fid = Fill(0x66);
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(fid);
        var bad = new List<byte>();
        bad.AddRange(Primitives.PutU16(0x00FF));
        bad.AddRange(Primitives.PutUvarint(Constants.RepVersion1));
        bad.Add((byte)'x');
        ulong serial = b.AddObjectRaw(bad.ToArray());
        b.AddRevision(fid, 1, serial, "a.txt");
        b.SetHead(fid, 1);
        var c = VsnContainer.Open(b.Build(1));
        TestVectors.AssertThrowsVsn(() => c.Materialize(serial), 0x0006);
    }

    [Fact]
    public void ReservedModeValueRejected()
    {
        var fid = Fill(0x77);
        var b = new ContainerBuilder(0x03); // reserved
        b.AddFile(fid);
        ulong serial = b.AddObject("x"u8.ToArray());
        b.AddRevision(fid, 1, serial, "a.txt");
        b.SetHead(fid, 1);
        TestVectors.AssertThrowsVsn(() => Validate.Run(b.Build(1), "Semantic"), 0x0001);
    }

    [Fact]
    public void EnterpriseModeUsesDirect1Semantics()
    {
        var fid = Fill(0x88);
        var b = new ContainerBuilder(Constants.ModeEnterprise);
        b.AddFile(fid);
        ulong serial = b.AddObject("enterprise"u8.ToArray());
        b.AddRevision(fid, 1, serial, "a.txt");
        b.SetHead(fid, 1);
        var data = b.Build(1);
        Validate.Run(data, "Full");
        Assert.Equal("enterprise"u8.ToArray(), VsnContainer.Open(data).Materialize(serial));
    }

    [Fact]
    public void EnterpriseModeRejectsExtents1Reconstruction()
    {
        var fid = Fill(0x99);
        var b = new ContainerBuilder(Constants.ModeEnterprise);
        b.AddFile(fid);
        ulong serial = b.AddObjectRaw(Writer.Extents1Descriptor(new() { Writer.LiteralOperation("nope"u8.ToArray()) }));
        b.AddRevision(fid, 1, serial, "a.txt");
        b.SetHead(fid, 1);
        TestVectors.AssertThrowsVsn(() => Validate.Run(b.Build(1), "Semantic"), 0x000C);
    }
}

public class RecoveryTests
{
    [Fact]
    public void ModeDoesNotForkGrammar()
    {
        var fid = new byte[16];
        Array.Fill(fid, (byte)0xAA);
        var modern = new ContainerBuilder(Constants.ModeModern);
        modern.AddFile(fid);
        ulong s = modern.AddObject("same"u8.ToArray());
        modern.AddRevision(fid, 1, s, "a.txt");
        modern.SetHead(fid, 1);
        var enterprise = new ContainerBuilder(Constants.ModeEnterprise);
        enterprise.AddFile(fid);
        ulong s2 = enterprise.AddObject("same"u8.ToArray());
        enterprise.AddRevision(fid, 1, s2, "a.txt");
        enterprise.SetHead(fid, 1);
        var a = ContainerParser.Parse(modern.Build(1));
        var c = ContainerParser.Parse(enterprise.Build(1));
        Assert.Equal(c.Records.Count, a.Records.Count);
        Assert.Equal(c.Objects.Count, a.Objects.Count);
        Assert.Equal(Constants.ModeModern, a.Mode);
        Assert.Equal(Constants.ModeEnterprise, c.Mode);
    }

    [Fact]
    public void RecoverySelectsHighestAcceptedGeneration()
    {
        var rr = Recovery.Recover(TestVectors.Load("DIRECT-01"));
        Assert.Equal(1ul, rr.AcceptedGeneration);
        Assert.Equal("RECOVERED", rr.Status);
        Assert.True(rr.Recovered);
    }

    [Fact]
    public void RecoveryWorksWithoutDerivedData()
    {
        var data = TestVectors.Load("EXT-02-and-EXT-03");
        var rr = Recovery.Recover(data);
        Assert.Equal("RECOVERED", rr.Status);
        Assert.Equal("hello vsn\n!!"u8.ToArray(), VsnContainer.Open(data).Materialize(20));
    }

    [Fact]
    public void NoCommitMarkerYieldsNoMarker()
    {
        var records = new List<(ushort, List<(ushort, byte[])>)>
        {
            (Constants.RecModeDeclaration, new() { (Constants.FidMode, new[] { Constants.ModeModern }) }),
            (Constants.RecFileIdentity, new() { (Constants.FidFileId, new byte[16]) }),
        };
        var data = Writer.Encode(Constants.ModeModern, records, new(), 0);
        Assert.Equal("NO_MARKER", Recovery.Recover(data).Status);
    }
}

