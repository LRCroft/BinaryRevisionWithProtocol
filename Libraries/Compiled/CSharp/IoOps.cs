namespace Vsn;

/// <summary>VSN-1 binary-safe import/export (bytes, streams, batch).</summary>
public static class IoOps
{
    /// <summary>Import raw bytes as a new file; returns the FileId.</summary>
    public static byte[] ImportBytes(VsnStore store, string path, byte[] content)
    {
        if (content == null) throw new VsnException(0x0001, "content must be bytes");
        return store.CreateFile(path, content);
    }

    /// <summary>Export materialized file content as bytes.</summary>
    public static byte[] ExportBytes(VsnStore store, byte[] fileId) => store.ReadFile(fileId);

    /// <summary>Import from a stream, chunk by chunk (streaming).</summary>
    public static byte[] ImportStream(VsnStore store, string path, Stream stream, int chunkSize = 65536)
    {
        using var ms = new MemoryStream();
        var buf = new byte[chunkSize];
        int n;
        while ((n = stream.Read(buf, 0, buf.Length)) > 0)
            ms.Write(buf, 0, n);
        return store.CreateFile(path, ms.ToArray());
    }

    /// <summary>Export file content to a stream; returns bytes written.</summary>
    public static long ExportStream(VsnStore store, byte[] fileId, Stream stream, int chunkSize = 65536)
    {
        long total = 0;
        foreach (var chunk in store.ReadFileStream(fileId, chunkSize))
        {
            stream.Write(chunk, 0, chunk.Length);
            total += chunk.Length;
        }
        return total;
    }

    /// <summary>Import multiple files; returns path -&gt; FileId.</summary>
    public static Dictionary<string, byte[]> ImportMultiple(VsnStore store, Dictionary<string, byte[]> files)
    {
        var result = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var kv in files)
            result[kv.Key] = store.CreateFile(kv.Key, kv.Value);
        return result;
    }

    /// <summary>Export multiple files; returns FileId(hex) -&gt; content.</summary>
    public static Dictionary<string, byte[]> ExportMultiple(VsnStore store, List<byte[]> fileIds)
    {
        var result = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var fid in fileIds)
            result[Convert.ToHexString(fid)] = store.ReadFile(fid);
        return result;
    }
}
