using Vsn;
using Xunit;

namespace Vsn.Tests;

/// <summary>
/// 0x0511 declared-size semantics (SR-27 / DR-6).
///
/// 0x0511 is the LOGICAL materialized content length. It is NEVER the
/// representation payload length. For DIRECT-1 the two coincide; for EXTENTS-1
/// they differ because the payload remainder is an operation collection.
///
/// Authoritative evidence: frozen vector EXT-02/EXT-03 carries an EXTENTS-1
/// object (serial 20) whose representation remainder is 17 bytes while 0x0511
/// declares 12, which is exactly its materialized length (b"hello vsn\n!!").
/// </summary>
public class DeclaredSizeTests
{
    private static readonly byte[] Fid = Enumerable.Repeat((byte)0x11, 16).ToArray();

    private static Dictionary<ulong, ulong?> DeclaredSizes(byte[] data)
    {
        var parsed = ContainerParser.Parse(data);
        var map = new Dictionary<ulong, ulong?>();
        foreach (var rec in parsed.Records)
        {
            if (rec.RType != Constants.RecContentObject) continue;
            var s = rec.GetField(Constants.FidObjectSerial);
            var z = rec.GetField(Constants.FidObjectSize);
            if (s != null) map[s.AsUvarint()] = z?.AsUvarint();
        }
        return map;
    }

    private static byte[] Build(byte[] extentsDescriptor)
    {
        var b = new ContainerBuilder(Constants.ModeModern);
        b.AddFile(Fid);
        ulong baseSerial = b.AddObject("ABCDEFGHIJ"u8.ToArray());
        b.AddObjectRaw(extentsDescriptor, 2);
        b.AddRevision(Fid, 1, baseSerial, "a.txt");
        b.SetHead(Fid, 1);
        return b.Build(1);
    }

    [Fact]
    public void FrozenVectorDeclaresLogicalNotRepresentationLength()
    {
        var data = TestVectors.Load("EXT-02-and-EXT-03");
        var parsed = ContainerParser.Parse(data);
        var target = parsed.Objects.First(o => o.Serial.Value == 20);
        var (ident, _, remainder) = Representations.ParseObjectHeader(target.Descriptor);

        Assert.Equal(Constants.RepExtents1, ident);
        Assert.Equal(17, remainder.Length);                     // representation payload
        Assert.Equal(12UL, DeclaredSizes(data)[20]);           // logical length
        Assert.NotEqual((ulong)remainder.Length, DeclaredSizes(data)[20]);

        var logical = VsnContainer.Open(data).Materialize(20);
        Assert.Equal(12, logical.Length);
        Assert.Equal((ulong)logical.Length, DeclaredSizes(data)[20]);
    }

    [Fact]
    public void Direct1DeclaredSizeEqualsLogicalLength()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "hello world"u8.ToArray());
        var data = store.Commit();
        Assert.Equal(11UL, DeclaredSizes(data)[1]);
    }

    [Fact]
    public void Direct1EmptyContentDeclaresZero()
    {
        var store = VsnStore.Create();
        store.CreateFile("empty.bin", Array.Empty<byte>());
        Assert.Equal(0UL, DeclaredSizes(store.Commit())[1]);
    }

    [Fact]
    public void Extents1CopyDeclaresMaterializedLength()
    {
        // Representation remainder is 9 bytes; materialized length is 10.
        var data = Build(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(1, 0, 10),
        }));
        var descriptor = ContainerParser.Parse(data).Objects
            .First(o => o.Serial.Value == 2).Descriptor;
        var (_, _, remainder) = Representations.ParseObjectHeader(descriptor);
        Assert.Equal(9, remainder.Length);
        Assert.Equal(10, VsnStore.Open(data).Materialize(2).Length);
        Assert.Equal(10UL, DeclaredSizes(data)[2]);
    }

    [Fact]
    public void Extents1LiteralDeclaresMaterializedLength()
    {
        var data = Build(Writer.Extents1Descriptor(new()
        {
            Writer.LiteralOperation("alpha"u8.ToArray()),
        }));
        var store = VsnStore.Open(data);
        Assert.Equal(5, store.Materialize(2).Length);
        Assert.Equal(5UL, DeclaredSizes(data)[2]);
    }

    [Fact]
    public void Extents1CopyPlusLiteralDeclaresMaterializedLength()
    {
        var data = Build(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(1, 0, 10),
            Writer.LiteralOperation("!!"u8.ToArray()),
        }));
        var store = VsnStore.Open(data);
        Assert.Equal(12, store.Materialize(2).Length);
        Assert.Equal(12UL, DeclaredSizes(data)[2]);
    }

    /// <summary>
    /// The exact failure: parse -> materialize -> write -> parse. Before the
    /// repair, re-serialization emitted the representation remainder length.
    /// </summary>
    [Fact]
    public void RewrittenContainerPreservesDeclaredLogicalLength()
    {
        var original = Build(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(1, 0, 10),
            Writer.LiteralOperation("!!"u8.ToArray()),
        }));
        var store = VsnStore.Open(original);
        var before = store.Materialize(2);

        var rewritten = store.ToBytes();
        var reparsed = VsnStore.Open(rewritten);
        var after = reparsed.Materialize(2);

        Assert.Equal(before, after);
        Assert.Equal(12UL, DeclaredSizes(rewritten)[2]);
        Assert.Equal(10UL, DeclaredSizes(rewritten)[1]);
    }

    [Fact]
    public void CorrectDeclaredLengthPassesContentValidation()
    {
        Validate.Content(Build(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(1, 0, 10),
        })));
    }

    /// <summary>DR-6 / frozen vector EXT-12: a wrong declared size is invalid.</summary>
    [Fact]
    public void IncorrectDeclaredLengthIsRejectedByContentValidation()
    {
        var data = Build(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(1, 0, 10),
        }));
        // Rewrite serial 2's declared size to the representation remainder (9).
        var corrupted = DeclaredSizeTestsSupport.WithDeclaredSize(data, 2, 9);
        TestVectors.AssertThrowsVsn(() => Validate.Content(corrupted), 0x000C);
    }
}