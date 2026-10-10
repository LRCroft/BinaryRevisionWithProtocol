namespace Vsn;

/// <summary>Builder for canonical VSN containers with explicit identities.</summary>
public sealed class ContainerBuilder
{
    public byte Mode { get; }
    public List<(ushort rtype, List<(ushort fid, byte[] value)> fields)> Records { get; } = new();
    public List<(ulong serial, byte[] descriptor)> Objects { get; } = new();

    private readonly HashSet<string> _fileIds = new(StringComparer.Ordinal);
    private readonly HashSet<ulong> _revisionIds = new();
    private readonly HashSet<ulong> _objectSerials = new();
    private ulong _nextObjectSerial = 1;

    public ContainerBuilder(byte mode = Constants.ModeModern)
    {
        Mode = mode;
    }

    public ContainerBuilder AddFile(byte[] fileId)
    {
        if (fileId.Length != 16) throw new ArgumentException("FileId must be 16 bytes");
        var key = Convert.ToHexString(fileId);
        if (!_fileIds.Add(key)) throw new InvalidOperationException("duplicate FileId");
        Records.Add((Constants.RecFileIdentity,
            new List<(ushort, byte[])> { (Constants.FidFileId, fileId) }));
        return this;
    }

    public ContainerBuilder AddRevision(byte[] fileId, ulong revisionId,
        ulong? objectSerial = null, string? path = null, byte presence = Constants.Present)
    {
        var key = Convert.ToHexString(fileId);
        if (!_fileIds.Contains(key)) throw new InvalidOperationException("FileId not declared");
        if (!_revisionIds.Add(revisionId)) throw new InvalidOperationException("duplicate RevisionId");
        var fields = new List<(ushort, byte[])>
        {
            (Constants.FidRevId, Primitives.PutUvarint(revisionId)),
            (Constants.FidRevFileId, fileId),
        };
        if (objectSerial.HasValue)
            fields.Add((Constants.FidRevObjectSerial, Primitives.PutUvarint(objectSerial.Value)));
        if (path != null)
            fields.Add((Constants.FidRevPath, System.Text.Encoding.UTF8.GetBytes(path)));
        fields.Add((Constants.FidRevPresence, new[] { presence }));
        Records.Add((Constants.RecRevision, fields));
        return this;
    }

    public ulong AddObject(byte[] content, ulong? serial = null)
    {
        ulong sid = serial ?? _nextObjectSerial++;
        if (sid >= _nextObjectSerial) _nextObjectSerial = sid + 1;
        if (!_objectSerials.Add(sid)) throw new InvalidOperationException("duplicate ObjectSerial");
        Records.Add((Constants.RecContentObject,
            new List<(ushort, byte[])>
            {
                (Constants.FidObjectSerial, Primitives.PutUvarint(sid)),
                (Constants.FidObjectSize, Primitives.PutUvarint((ulong)content.Length)),
            }));
        Objects.Add((sid, Writer.Direct1Descriptor(content)));
        return sid;
    }

    public ulong AddObjectRaw(byte[] descriptor, ulong? serial = null)
    {
        ulong sid = serial ?? _nextObjectSerial++;
        if (sid >= _nextObjectSerial) _nextObjectSerial = sid + 1;
        if (!_objectSerials.Add(sid)) throw new InvalidOperationException("duplicate ObjectSerial");
        Objects.Add((sid, descriptor));
        // 0x0511 is the LOGICAL content length (SR-29), never representation bytes.
        // It is optional (SR-27): omit it when the logical length cannot be
        // resolved yet (missing dependency, cycle, unsupported representation).
        var fields = new List<(ushort, byte[])> { (Constants.FidObjectSerial, Primitives.PutUvarint(sid)) };
        try
        {
            fields.Add((Constants.FidObjectSize, Primitives.PutUvarint((ulong)LogicalContent(descriptor).Length)));
        }
        catch (VsnException)
        {
            // 0x0511 omitted: fully valid under SR-27
        }
        Records.Add((Constants.RecContentObject, fields));
        return sid;
    }

    /// <summary>Materialize a descriptor to its LOGICAL content (SR-29).</summary>
    private byte[] LogicalContent(byte[] descriptor, HashSet<string>? visited = null)
    {
        visited ??= new HashSet<string>(StringComparer.Ordinal);
        var key = Convert.ToHexString(descriptor);
        if (!visited.Add(key))
            throw new VsnException(0x000C, "dependency cycle");
        var (ident, ver, remainder) = Representations.ParseObjectHeader(descriptor);
        if (ident == Constants.RepDirect1 && ver == Constants.RepVersion1)
            return Representations.MaterializeDirect(remainder);
        if (ident == Constants.RepExtents1 && ver == Constants.RepVersion1)
            return Representations.MaterializeExtents(remainder, s =>
            {
                byte[]? src = null;
                foreach (var o in Objects)
                    if (o.serial == s) { src = o.descriptor; break; }
                if (src == null)
                    throw new VsnException(0x0008, $"missing object {s}");
                return LogicalContent(src, new HashSet<string>(visited));
            });
        throw new VsnException(0x0006, $"unsupported representation 0x{ident:X4} v{ver}");
    }

    public ContainerBuilder SetHead(byte[] fileId, ulong revisionId)
    {
        var key = Convert.ToHexString(fileId);
        if (!_fileIds.Contains(key)) throw new InvalidOperationException("FileId not declared");
        if (!_revisionIds.Contains(revisionId)) throw new InvalidOperationException("RevisionId not declared");
        Records.Add((Constants.RecFileHead,
            new List<(ushort, byte[])>
            {
                (Constants.FidHeadFileId, fileId),
                (Constants.FidHeadRevId, Primitives.PutUvarint(revisionId)),
            }));
        return this;
    }

    public byte[] Build(ulong generation = 1)
    {
        var records = new List<(ushort, List<(ushort, byte[])>)>
        {
            (Constants.RecModeDeclaration,
                new List<(ushort, byte[])> { (Constants.FidMode, new[] { Mode }) }),
        };
        records.AddRange(Records);
        records.Add((Constants.RecCommitMarker,
            new List<(ushort, byte[])> { (Constants.FidCommitGeneration, Primitives.PutUvarint(generation)) }));
        return Writer.Encode(Mode, records, Objects, generation);
    }
}

