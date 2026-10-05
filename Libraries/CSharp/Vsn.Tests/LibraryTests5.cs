using Vsn;
using Xunit;

namespace Vsn.Tests;

public class IoOpsTests
{
    [Fact]
    public void ByteOrientedImportExportPreservesArbitraryBinaryData()
    {
        var store = VsnStore.Create();
        var payload = new byte[] { 0x00, 0x01, 0xFF, 0x00, 0x7F, 0x80, 0x00 };
        var fid = IoOps.ImportBytes(store, "bin.dat", payload);
        Assert.Equal(payload, IoOps.ExportBytes(store, fid));
        var data = store.Commit();
        Assert.Equal(payload, IoOps.ExportBytes(VsnStore.Open(data), fid));
    }

    [Fact]
    public void StreamOrientedImportExport()
    {
        var store = VsnStore.Create();
        var big = new byte[200000];
        for (int i = 0; i < big.Length; i++) big[i] = (byte)(i % 251);
        using var input = new MemoryStream(big, writable: false);
        var fid = IoOps.ImportStream(store, "big.bin", input);
        using var output = new MemoryStream();
        long written = IoOps.ExportStream(store, fid, output);
        Assert.Equal(big.Length, written);
        Assert.Equal(big, output.ToArray());
    }

    [Fact]
    public void BatchImportExport()
    {
        var store = VsnStore.Create();
        var files = new Dictionary<string, byte[]>(StringComparer.Ordinal)
        {
            { "a.txt", "A"u8.ToArray() }, { "b.txt", "B"u8.ToArray() },
        };
        var ids = IoOps.ImportMultiple(store, files);
        Assert.Equal(2, ids.Count);
        var out_ = IoOps.ExportMultiple(store, new List<byte[]>(ids.Values));
        Assert.Equal(2, out_.Count);
    }
}

public class StreamingTests
{
    [Fact]
    public void LargeObjectStreamsInChunks()
    {
        var store = VsnStore.Create();
        var big = new byte[300000];
        for (int i = 0; i < big.Length; i++) big[i] = (byte)((i * 7) % 256);
        var fid = store.CreateFile("big.bin", big);
        var chunks = new List<byte[]>();
        foreach (var c in store.ReadFileStream(fid, 65536))
            chunks.Add(c);
        Assert.True(chunks.Count >= 5);
        Assert.Equal(big, chunks.SelectMany(c => c).ToArray());
    }

    [Fact]
    public void Extents1ObjectStreamsIdenticallyToMaterialization()
    {
        var store = VsnStore.Create();
        var fid = store.CreateFile("base.txt", "hello vsn\n"u8.ToArray());
        ulong src = store.GetObjectSerial(fid)!.Value;
        ulong dst = store.AddObjectDescriptor(Writer.Extents1Descriptor(new()
        {
            Writer.CopyOperation(src, 0, 10), Writer.LiteralOperation("!!"u8.ToArray()),
        }));
        var streamed = store.MaterializeStream(dst, 4).SelectMany(c => c).ToArray();
        Assert.Equal(store.Materialize(dst), streamed);
    }
}

public class DiagnosticsTests
{
    [Fact]
    public void StructuredDiagnosticsCarryCodeNameSeverityCategoryContext()
    {
        var store = VsnStore.Create();
        store.CreateFile("a.txt", "x"u8.ToArray());
        var data = store.Commit();
        var bad = data[..20];
        var diags = Diagnostic.ValidateWithDiagnostics(bad, "Full");
        Assert.Single(diags);
        Assert.Equal(0x0002, diags[0].Code);
        Assert.Equal("TRUNCATED", diags[0].Name);
        Assert.Equal(Severity.Error, diags[0].Severity);
        Assert.Equal(Category.Protocol, diags[0].Category);
        Assert.IsType<string>(diags[0].Message);
    }
}

