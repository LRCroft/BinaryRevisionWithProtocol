using Vsn;
using Xunit;

namespace Vsn.Tests;

public class FramingTests
{
    [Fact]
    public void UvarintBoundariesRoundTripAndStayMinimal()
    {
        foreach (ulong v in new ulong[] { 0, 1, 127, 128, 16383, 16384, 2097151, 2097152,
            268435455, 268435456, 34359738367, 34359738368, 1ul << 63, ulong.MaxValue })
        {
            var enc = Primitives.PutUvarint(v);
            int off = 0;
            Assert.Equal(v, Primitives.ReadUvarint(enc, ref off));
            Assert.Equal(enc.Length, off);
        }
        Assert.Single(Primitives.PutUvarint(0));
        Assert.Single(Primitives.PutUvarint(127));
        Assert.Equal(2, Primitives.PutUvarint(128).Length);
    }

    [Fact]
    public void NonMinimalUvarintRejected()
    {
        int off = 0;
        TestVectors.AssertThrowsVsn(() => Primitives.ReadUvarint(new byte[] { 0x80, 0x00 }, ref off), 0x0001);
    }

    [Fact]
    public void UvarintOverflowRejected()
    {
        int off = 0;
        var data = new byte[] { 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 };
        TestVectors.AssertThrowsVsn(() => Primitives.ReadUvarint(data, ref off), 0x0001);
    }

    [Fact]
    public void InvalidMagicRejected()
    {
        TestVectors.AssertThrowsVsn(() => ContainerParser.Parse(new byte[100]), 0x0001);
    }

    [Fact]
    public void InvalidContainerFormatVersionRejected()
    {
        var data = new byte[] { 0x56, 0x53, 0x4E, 0x2D, 0x00, 0x02, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00 };
        TestVectors.AssertThrowsVsn(() => ContainerParser.Parse(data), 0x0003);
    }

    [Fact]
    public void InvalidEncodingVersionRejected()
    {
        var data = new byte[] { 0x56, 0x53, 0x4E, 0x2D, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00 };
        TestVectors.AssertThrowsVsn(() => ContainerParser.Parse(data), 0x0004);
    }
}

public class TruncationTests
{
    [Fact]
    public void TruncationOfFrozenVectorDetectedAsTruncated()
    {
        var data = TestVectors.Load("DIRECT-01");
        var rr = Recovery.Recover(data[..^5]);
        Assert.Equal("TRUNCATED", rr.Status);
        Assert.False(rr.Recovered);
    }

    [Fact]
    public void TruncatedFramingRaisesTruncated()
    {
        var data = TestVectors.Load("DIRECT-02");
        TestVectors.AssertThrowsVsn(() => ContainerParser.Parse(data[..20]), 0x0002);
    }

    [Fact]
    public void InvalidFieldOrderingRejected()
    {
        var payload = new List<byte>();
        payload.AddRange(Primitives.PutU16(0x0201));
        payload.AddRange(Primitives.PutUvarint(1));
        payload.Add(0x01);
        payload.AddRange(Primitives.PutU16(0x0101));
        payload.AddRange(Primitives.PutUvarint(1));
        payload.Add(0x01);
        var data = new List<byte>();
        data.AddRange("VSN-"u8.ToArray());
        data.AddRange(Primitives.PutU16(1));
        data.AddRange(Primitives.PutU16(1));
        data.AddRange(Primitives.PutU16(0x0000));
        data.AddRange(Primitives.PutUvarint(0));
        data.AddRange(Primitives.PutU16(0x0002));
        data.AddRange(Primitives.PutUvarint((ulong)payload.Count));
        data.AddRange(payload);
        data.AddRange(Primitives.PutU16(0x0000));
        data.Add(0); data.Add(1); data.Add(1);
        TestVectors.AssertThrowsVsn(() => ContainerParser.Parse(data.ToArray()), 0x0011);
    }
}

