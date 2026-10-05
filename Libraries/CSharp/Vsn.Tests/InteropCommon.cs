using System.Text.Json;
using Vsn;

namespace Vsn.Tests;

/// <summary>
/// Cross-language interoperability support: shared scenario definitions and a
/// language-neutral description of a container's canonical interpretation.
/// </summary>
public static class InteropCommon
{
    public static readonly string[] Scenarios = { "basic", "extents", "enterprise", "multifile" };

    private static byte[] Fill(byte b)
    {
        var a = new byte[16];
        Array.Fill(a, b);
        return a;
    }

    /// <summary>Build a scenario deterministically; identical bytes across all languages.</summary>
    public static byte[] BuildScenario(string name)
    {
        var b = new ContainerBuilder(Constants.ModeModern);
        if (name == "basic")
        {
            var f = Fill(0x01);
            b.AddFile(f);
            ulong s = b.AddObject("hello vsn\n"u8.ToArray());
            b.AddRevision(f, 1, s, "hello.txt");
            b.SetHead(f, 1);
            return b.Build(1);
        }
        if (name == "extents")
        {
            var a = Fill(0x02);
            var c = Fill(0x03);
            b.AddFile(a);
            b.AddFile(c);
            ulong s1 = b.AddObject("hello vsn\n"u8.ToArray(), 1);
            ulong s2 = b.AddObjectRaw(Writer.Extents1Descriptor(new()
            {
                Writer.CopyOperation(1, 0, 10),
                Writer.LiteralOperation("!!"u8.ToArray()),
            }), 2);
            b.AddRevision(a, 1, s1, "a.txt");
            b.AddRevision(c, 2, s2, "b.txt");
            b.SetHead(a, 1);
            b.SetHead(c, 2);
            return b.Build(2);
        }
        if (name == "enterprise")
        {
            var f = Fill(0x04);
            var e = new ContainerBuilder(Constants.ModeEnterprise);
            e.AddFile(f);
            ulong s = e.AddObject("enterprise"u8.ToArray());
            e.AddRevision(f, 1, s, "e.txt");
            e.SetHead(f, 1);
            return e.Build(1);
        }
        // multifile: binary content including NUL and 0xFF
        var f1 = Fill(0x05);
        var f2 = Fill(0x06);
        var f3 = Fill(0x07);
        b.AddFile(f1); b.AddFile(f2); b.AddFile(f3);
        b.AddObject(new byte[] { 0x00, 0x01, 0xFF, 0x00, 0x7F }, 1);
        b.AddObject("plain text"u8.ToArray(), 2);
        b.AddObject(Array.Empty<byte>(), 3);
        b.AddRevision(f1, 1, 1, "bin.dat");
        b.AddRevision(f2, 2, 2, "text.txt");
        b.AddRevision(f3, 3, 3, "empty.txt");
        b.SetHead(f1, 1); b.SetHead(f2, 2); b.SetHead(f3, 3);
        return b.Build(3);
    }

    /// <summary>Describe a container's canonical interpretation (language-neutral).</summary>
    public static Dictionary<string, object?> Describe(byte[] data)
    {
        var parsed = ContainerParser.Parse(data);
        var c = VsnContainer.Open(data);
        var pathByFile = new Dictionary<string, string>(StringComparer.Ordinal);
        var revByFile = new Dictionary<string, ulong>(StringComparer.Ordinal);
        var serialByRev = new Dictionary<ulong, ulong?>();
        foreach (var rec in parsed.Records)
        {
            if (rec.RType == Constants.RecRevision)
            {
                var rid = rec.GetField(Constants.FidRevId)!.AsUvarint();
                var key = Convert.ToHexString(rec.GetField(Constants.FidRevFileId)!.Value.Span);
                var p = rec.GetField(Constants.FidRevPath);
                if (p != null) pathByFile[key] = System.Text.Encoding.UTF8.GetString(p.Value.Span);
                var os = rec.GetField(Constants.FidRevObjectSerial);
                serialByRev[rid] = os == null ? null : (ulong?)os.AsUvarint();
            }
            else if (rec.RType == Constants.RecFileHead)
            {
                var key = Convert.ToHexString(rec.GetField(Constants.FidHeadFileId)!.Value.Span);
                revByFile[key] = rec.GetField(Constants.FidHeadRevId)!.AsUvarint();
            }
        }
        var files = new List<Dictionary<string, object?>>();
        foreach (var rec in parsed.Records)
        {
            if (rec.RType != Constants.RecFileIdentity) continue;
            var key = Convert.ToHexString(rec.GetField(Constants.FidFileId)!.Value.Span);
            ulong? head = revByFile.TryGetValue(key, out var h) ? h : null;
            ulong? serial = head != null && serialByRev.TryGetValue(head.Value, out var s) ? s : null;
            byte[] content = Array.Empty<byte>();
            int? repIdentity = null;
            int? repVersion = null;
            if (serial != null)
            {
                var entry = c.Objects.First(o => o.Serial.Value == serial.Value);
                repIdentity = (entry.Descriptor.Span[0] << 8) | entry.Descriptor.Span[1];
                int off = 2;
                repVersion = (int)Primitives.ReadUvarint(entry.Descriptor.Span, ref off);
                content = c.Materialize(serial.Value);
            }
            files.Add(new Dictionary<string, object?>
            {
                ["fileId"] = key,
                ["path"] = pathByFile.TryGetValue(key, out var p) ? p : null,
                ["headRevision"] = head,
                ["objectSerial"] = serial,
                ["repIdentity"] = repIdentity,
                ["repVersion"] = repVersion,
                ["contentBase64"] = Convert.ToBase64String(content),
            });
        }
        files.Sort((x, y) => string.Compare((string)x["fileId"]!, (string)y["fileId"]!, StringComparison.Ordinal));
        var rr = Recovery.Recover(data);
        return new Dictionary<string, object?>
        {
            ["mode"] = parsed.Mode,
            ["generation"] = parsed.TrailerGeneration,
            ["recoveryStatus"] = rr.Status,
            ["acceptedGeneration"] = rr.AcceptedGeneration,
            ["files"] = files,
        };
    }

    /// <summary>Write every scenario into {dir}/csharp/.</summary>
    public static void WriteAll(string dir)
    {
        var outDir = Path.Combine(dir, "csharp");
        Directory.CreateDirectory(outDir);
        foreach (var s in Scenarios)
            File.WriteAllBytes(Path.Combine(outDir, s + ".vsn"), BuildScenario(s));
    }

    public static string CanonicalJson(Dictionary<string, object?> desc) =>
        JsonSerializer.Serialize(desc, new JsonSerializerOptions { WriteIndented = false });
}

