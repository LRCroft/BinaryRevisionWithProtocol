using Vsn;
using Xunit;

namespace Vsn.Tests;

/// <summary>
/// Primitive-level protocol coverage: the u16be encoding and the DR-0
/// three-byte ObjectDescriptor header (Representation Identity + Version).
/// </summary>
public class PrimitiveTests
{
    [Theory]
    [InlineData((ushort)0x0000)]
    [InlineData((ushort)0x0001)]
    [InlineData((ushort)0x0101)]
    [InlineData((ushort)0x0002)]
    [InlineData((ushort)0x7FFF)]
    [InlineData((ushort)0x8000)]
    [InlineData((ushort)0xFFFF)]
    public void U16beRoundTrips(ushort value)
    {
        var encoded = Primitives.PutU16(value);
        Assert.Equal(2, encoded.Length);
        int offset = 0;
        Assert.Equal(value, Primitives.ReadU16(encoded, ref offset));
        Assert.Equal(2, offset);
    }

    [Fact]
    public void U16beIsBigEndian()
    {
        var encoded = Primitives.PutU16(0x0101);
        Assert.Equal(0x01, encoded[0]);
        Assert.Equal(0x01, encoded[1]);
        var hi = Primitives.PutU16(0xABCD);
        Assert.Equal(0xAB, hi[0]);
        Assert.Equal(0xCD, hi[1]);
    }

    [Fact]
    public void U16beTruncatedRejected()
    {
        TestVectors.AssertThrowsVsn(
            () => { int o = 0; Primitives.ReadU16(new byte[] { 0x01 }, ref o); }, 0x0002);
    }

    [Theory]
    [InlineData(Constants.RepDirect1)]
    [InlineData(Constants.RepExtents1)]
    public void Dr0ObjectHeaderParsesIdentityAndVersion(ushort identity)
    {
        // DR-0: header is exactly u16be identity + uvarint version, remainder follows.
        var body = new byte[] { 0xDE, 0xAD, 0xBE, 0xEF };
        var descriptor = Primitives.PutU16(identity)
            .Concat(Primitives.PutUvarint(Constants.RepVersion1))
            .Concat(body)
            .ToArray();

        var (ident, version, remainder) = Representations.ParseObjectHeader(descriptor);

        Assert.Equal(identity, ident);
        Assert.Equal(Constants.RepVersion1, version);
        Assert.Equal(body, remainder.ToArray());
        Assert.Equal(3 + body.Length, descriptor.Length); // fixed 3-byte header
    }
}