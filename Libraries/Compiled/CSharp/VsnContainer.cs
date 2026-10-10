namespace Vsn;

/// <summary>
/// VSN-1 high-level API: open, materialize, inspect.
/// </summary>
public sealed class VsnContainer
{
    private readonly ParsedContainer _parsed;
    private readonly Dictionary<ulong, ObjectEntry> _objectIndex;
    private readonly Dictionary<ulong, byte[]> _contentCache = new();

    public VsnContainer(ReadOnlyMemory<byte> data)
    {
        _parsed = ContainerParser.Parse(data);
        _objectIndex = new Dictionary<ulong, ObjectEntry>();
        foreach (var obj in _parsed.Objects)
            _objectIndex[obj.Serial.Value] = obj;
    }

    public byte? Mode => _parsed.Mode;
    public int ContainerFormatVersion => _parsed.ContainerFormatVersion;
    public int EncodingVersion => _parsed.EncodingVersion;
    public IReadOnlyList<Record> Records => _parsed.Records;
    public IReadOnlyList<ObjectEntry> Objects => _parsed.Objects;

    public ObjectEntry GetObject(ulong serial)
    {
        if (!_objectIndex.TryGetValue(serial, out var entry))
            throw new VsnException(0x0008, $"missing object {serial}");
        return entry;
    }

    public byte[] Materialize(ulong serial, HashSet<ulong>? visited = null)
    {
        visited ??= new HashSet<ulong>();
        if (!visited.Add(serial))
            throw new VsnException(0x000C, $"dependency cycle at ObjectSerial {serial}");
        if (_contentCache.TryGetValue(serial, out var cached))
            return cached;
        var entry = GetObject(serial);
        var (ident, ver, remainder) = Representations.ParseObjectHeader(entry.Descriptor);
        byte[] result;
        if (ident == Constants.RepDirect1 && ver == Constants.RepVersion1)
            result = Representations.MaterializeDirect(remainder);
        else if (ident == Constants.RepExtents1 && ver == Constants.RepVersion1)
            result = Representations.MaterializeExtents(remainder, s => Materialize(s, new HashSet<ulong>(visited)));
        else
            throw new VsnException(0x0006, $"unsupported representation 0x{ident:X4} v{ver}");
        _contentCache[serial] = result;
        return result;
    }

    public List<(FileId fileId, RevisionId revId)> GetFiles()
    {
        var heads = new List<(FileId, RevisionId)>();
        foreach (var rec in _parsed.Records)
        {
            if (rec.RType == Constants.RecFileHead)
            {
                var f = rec.GetField(Constants.FidHeadFileId);
                var r = rec.GetField(Constants.FidHeadRevId);
                if (f != null && r != null)
                    heads.Add((new FileId(f.Value), new RevisionId(r.AsUvarint())));
            }
        }
        return heads;
    }

    public static VsnContainer Open(ReadOnlyMemory<byte> data) => new(data);
}
