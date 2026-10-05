using System.Security.Cryptography;
using System.Text.Json;
using Vsn;
using Xunit;

namespace Vsn.Tests;

public class FrozenVectorTests
{
    [Fact]
    public void ManifestHashes()
    {
        var manifestJson = File.ReadAllText(Path.Combine(TestVectors.Dir, "manifest.json"));
        using var doc = JsonDocument.Parse(manifestJson);
        foreach (var v in doc.RootElement.GetProperty("vectors").EnumerateArray())
        {
            var name = v.GetProperty("name").GetString()!;
            var sha = Convert.ToHexString(SHA256.HashData(TestVectors.Load(name))).ToLowerInvariant();
            Assert.Equal(v.GetProperty("sha256").GetString()!, sha);
            Assert.Equal(v.GetProperty("bytes").GetInt32(), TestVectors.Load(name).Length);
        }
    }

    [Fact]
    public void AllFiveVectorsMaterializeToIntendedLogicalBytes()
    {
        Assert.Empty(VsnContainer.Open(TestVectors.Load("DIRECT-01")).Materialize(42));
        var d2 = VsnContainer.Open(TestVectors.Load("DIRECT-02")).Materialize(7);
        Assert.Equal(256, d2.Length);
        for (int i = 0; i < 256; i++) Assert.Equal((byte)i, d2[i]);
        Assert.Equal(new byte[] { 0x41, 0x00, 0x42, 0xFF }, VsnContainer.Open(TestVectors.Load("DIRECT-03")).Materialize(9));
        Assert.Equal("alpha"u8.ToArray(), VsnContainer.Open(TestVectors.Load("EXT-01")).Materialize(20));
        var e2 = VsnContainer.Open(TestVectors.Load("EXT-02-and-EXT-03"));
        Assert.Equal("hello vsn\n"u8.ToArray(), e2.Materialize(10));
        Assert.Equal("hello vsn\n!!"u8.ToArray(), e2.Materialize(20));
    }

    [Fact]
    public void FileIdentityFieldIdIs0x0101AndFileIdsAre16Bytes()
    {
        Assert.Equal((ushort)0x0101, Constants.FidFileId);
        Assert.Equal((ushort)0x0001, Constants.RecFileIdentity);
        foreach (var name in TestVectors.Names)
        {
            var parsed = ContainerParser.Parse(TestVectors.Load(name));
            foreach (var rec in parsed.Records)
            {
                if (rec.RType != Constants.RecFileIdentity) continue;
                var f = rec.GetField(Constants.FidFileId);
                Assert.NotNull(f);
                Assert.Equal(16, f!.Value.Length);
            }
        }
    }

    [Fact]
    public void TrailerCanonicalCountExcludesModeDeclaration()
    {
        var parsed = ContainerParser.Parse(TestVectors.Load("DIRECT-01"));
        Assert.Equal(7, parsed.Records.Count);
        Assert.Equal(6, parsed.Records.Count(r => r.RType != Constants.RecModeDeclaration));
        Assert.Equal(6ul, parsed.TrailerRecordCount);
        Assert.Equal(1ul, parsed.TrailerGeneration);
    }
}
