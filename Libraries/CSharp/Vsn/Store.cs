namespace Vsn;

/// <summary>Mutable VSN-1 container with the full library API.</summary>
public sealed class VsnStore
{
    private byte[] _data = Array.Empty<byte>();
    private ParsedContainer? _parsed;
    private bool _closed;
    private byte _mode;
    private readonly object _lock = new();

    private readonly Dictionary<string, FileRecord> _fileIds = new(StringComparer.Ordinal);
    private readonly Dictionary<ulong, RevisionRecord> _revisions = new();
    private readonly Dictionary<ulong, byte[]> _objects = new();
    private readonly Dictionary<ulong, byte[]> _contentCache = new();
    private ulong _nextObjectSerial = 1;
    private ulong _nextRevisionId = 1;
    private ulong _generation;

    private static string FileKey(byte[] fid) => Convert.ToHexString(fid);

    /// <summary>Generated FileId: 16 opaque bytes of identity, never a content hash.</summary>
    public static byte[] GenerateFileId() => Guid.NewGuid().ToByteArray();

    private VsnStore(byte[]? data, byte mode)
    {
        if (data != null)
        {
            _data = (byte[])data.Clone();
            _parsed = ContainerParser.Parse(_data);
            _mode = _parsed.Mode ?? mode;
        }
        else
        {
            _mode = mode;
        }
        BuildState();
    }

    public static VsnStore Create(byte mode = Constants.ModeModern) => new(null, mode);
    public static VsnStore Open(byte[] data) => new(data, Constants.ModeModern);

    private void CheckOpen()
    {
        if (_closed)
            throw new VsnException(0x0001, "container is closed");
    }

    public byte Mode { get { CheckOpen(); return _mode; } }
    public ulong Generation { get { CheckOpen(); return _generation; } }
    public bool IsClosed => _closed;
    public byte[] CanonicalData => _data;
    public ParsedContainer? Parsed => _parsed;

    private void BuildState()
    {
        _fileIds.Clear();
        _revisions.Clear();
        _objects.Clear();
        _contentCache.Clear();
        _nextObjectSerial = 1;
        _nextRevisionId = 1;
        _generation = 0;
        if (_parsed == null) return;
        foreach (var rec in _parsed.Records)
        {
            if (rec.RType == Constants.RecFileIdentity)
            {
                var f = rec.GetField(Constants.FidFileId);
                if (f != null)
                {
                    var fid = f.Value.ToArray();
                    _fileIds[FileKey(fid)] = new FileRecord(fid, null, null);
                }
            }
            else if (rec.RType == Constants.RecRevision)
            {
                ApplyRevisionRecord(rec);
            }
            else if (rec.RType == Constants.RecFileHead)
            {
                var fid = rec.GetField(Constants.FidHeadFileId);
                var rid = rec.GetField(Constants.FidHeadRevId);
                if (fid != null && rid != null && _fileIds.TryGetValue(FileKey(fid.Value.ToArray()), out var info))
                    info.HeadRevision = rid.AsUvarint();
            }
            else if (rec.RType == Constants.RecCommitMarker)
            {
                var g = rec.GetField(Constants.FidCommitGeneration);
                if (g != null) _generation = g.AsUvarint();
            }
        }
        foreach (var obj in _parsed.Objects)
        {
            ulong serial = obj.Serial.Value;
            _objects[serial] = obj.Descriptor.ToArray();
            if (serial >= _nextObjectSerial) _nextObjectSerial = serial + 1;
        }
    }

    private void ApplyRevisionRecord(Record rec)
    {
        var ridF = rec.GetField(Constants.FidRevId);
        var fidF = rec.GetField(Constants.FidRevFileId);
        if (ridF == null || fidF == null) return;
        ulong rid = ridF.AsUvarint();
        var objF = rec.GetField(Constants.FidRevObjectSerial);
        var pathF = rec.GetField(Constants.FidRevPath);
        var presF = rec.GetField(Constants.FidRevPresence);
        string? fpath = pathF == null ? null : System.Text.Encoding.UTF8.GetString(pathF.Value.Span);
        var fid = fidF.Value.ToArray();
        _revisions[rid] = new RevisionRecord(rid, fid,
            objF == null ? null : objF.AsUvarint(), fpath,
            presF == null ? Constants.Present : presF.Value.Span[0]);
        if (rid >= _nextRevisionId) _nextRevisionId = rid + 1;
        if (pathF != null && _fileIds.TryGetValue(FileKey(fid), out var info))
            info.Path = fpath;
    }

    public void Close()
    {
        lock (_lock) { _closed = true; _contentCache.Clear(); }
    }

    public void Reopen(byte[]? data = null)
    {
        CheckOpen();
        _data = data == null ? _data : (byte[])data.Clone();
        _parsed = ContainerParser.Parse(_data);
        BuildState();
    }

    public ContainerInfo Inspect()
    {
        CheckOpen();
        return new ContainerInfo(_mode, _generation, _fileIds.Count, _objects.Count, _revisions.Count);
    }

    // --- File API ---

    /// <summary>Create a file and its first Revision; returns the FileId.</summary>
    public byte[] CreateFile(string path, byte[]? content = null)
    {
        lock (_lock)
        {
            CheckOpen();
            content ??= Array.Empty<byte>();
            foreach (var info in _fileIds.Values)
                if (info.Path == path)
                    throw new VsnException(0x000A, $"duplicate path {path}");
            var fileId = GenerateFileId();
            _fileIds[FileKey(fileId)] = new FileRecord(fileId, path, null);
            ulong serial = AddObjectInternal(content);
            ulong rid = _nextRevisionId++;
            _revisions[rid] = new RevisionRecord(rid, fileId, serial, path, Constants.Present);
            _fileIds[FileKey(fileId)].HeadRevision = rid;
            return fileId;
        }
    }

    public byte[] ReadFile(byte[] fileId)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        if (info.HeadRevision == null)
            throw new VsnException(0x0009, "no accepted revision");
        var rev = _revisions[info.HeadRevision.Value];
        if (rev.Presence == Constants.Deleted)
            throw new VsnException(0x0009, "file is deleted");
        if (rev.ObjectSerial == null) return Array.Empty<byte>();
        return Materialize(rev.ObjectSerial.Value);
    }

    public void WriteFile(byte[] fileId, byte[] content)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        ulong serial = AddObjectInternal(content);
        ulong rid = _nextRevisionId++;
        _revisions[rid] = new RevisionRecord(rid, fileId, serial, info.Path, Constants.Present);
        info.HeadRevision = rid;
    }

    public void DeleteFile(byte[] fileId)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        ulong rid = _nextRevisionId++;
        _revisions[rid] = new RevisionRecord(rid, fileId, null, info.Path, Constants.Deleted);
        info.HeadRevision = rid;
    }


    public void RenameFile(byte[] fileId, string newPath)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        foreach (var kv in _fileIds)
            if (kv.Key != FileKey(fileId) && kv.Value.Path == newPath)
                throw new VsnException(0x000A, $"duplicate path {newPath}");
        RevisionRecord? oldRev = info.HeadRevision.HasValue ? _revisions[info.HeadRevision.Value] : null;
        ulong rid = _nextRevisionId++;
        _revisions[rid] = new RevisionRecord(rid, fileId,
            oldRev?.ObjectSerial, newPath, oldRev?.Presence ?? Constants.Present);
        info.HeadRevision = rid;
        info.Path = newPath;
    }

    public List<FileRecord> ListFiles()
    {
        CheckOpen();
        return new List<FileRecord>(_fileIds.Values);
    }

    public bool FileExists(byte[] fileId)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info) || info.HeadRevision == null)
            return false;
        return _revisions[info.HeadRevision.Value].Presence != Constants.Deleted;
    }

    public byte[]? GetFileId(string path)
    {
        CheckOpen();
        foreach (var info in _fileIds.Values)
            if (info.Path == path) return (byte[])info.FileId.Clone();
        return null;
    }

    public FileRecord GetFileMetadata(byte[] fileId)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        return new FileRecord((byte[])info.FileId.Clone(), info.Path, info.HeadRevision);
    }


    // --- Revision API ---

    public List<ulong> ListRevisions(byte[]? fileId = null)
    {
        CheckOpen();
        var result = new List<ulong>();
        foreach (var rev in _revisions.Values)
        {
            if (fileId == null || FileKey(rev.FileId) == FileKey(fileId))
                result.Add(rev.RevisionId);
        }
        result.Sort();
        return result;
    }

    public RevisionRecord GetRevision(ulong revisionId)
    {
        CheckOpen();
        if (!_revisions.TryGetValue(revisionId, out var rev))
            throw new VsnException(0x0009, $"unknown RevisionId {revisionId}");
        return rev;
    }

    public ulong? GetCurrentRevision(byte[] fileId)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            return null;
        return info.HeadRevision;
    }

    public byte[] CheckoutRevision(byte[] fileId, ulong revisionId)
    {
        CheckOpen();
        if (!_revisions.TryGetValue(revisionId, out var rev))
            throw new VsnException(0x0009, $"unknown RevisionId {revisionId}");
        if (FileKey(rev.FileId) != FileKey(fileId))
            throw new VsnException(0x000B, "RevisionId does not belong to FileId");
        if (rev.ObjectSerial == null) return Array.Empty<byte>();
        return Materialize(rev.ObjectSerial.Value);
    }

    public void RestoreRevision(byte[] fileId, ulong revisionId)
    {
        CheckOpen();
        if (!_revisions.TryGetValue(revisionId, out var rev))
            throw new VsnException(0x0009, $"unknown RevisionId {revisionId}");
        if (FileKey(rev.FileId) != FileKey(fileId))
            throw new VsnException(0x000B, "RevisionId does not belong to FileId");
        var content = rev.ObjectSerial == null ? Array.Empty<byte>() : Materialize(rev.ObjectSerial.Value);
        WriteFile(fileId, content);
    }

    public bool CompareRevisions(byte[] fileId, ulong revA, ulong revB) =>
        !CheckoutRevision(fileId, revA).SequenceEqual(CheckoutRevision(fileId, revB));

    /// <summary>
    /// LimitCleanUp: retain only the newest <paramref name="limit"/> revisions of a
    /// file. LIBRARY capability, not a VSN-1 protocol rule.
    /// </summary>
    /// <remarks>
    /// Scope is a single file's history, matching the VSN revision model in which
    /// every Revision names one FileId and each file has its own head.
    /// <para>
    /// <paramref name="limit"/> is the maximum number of revisions retained and must
    /// be &gt;= 1; zero is rejected (0x000C) so a slipped argument cannot silently
    /// destroy an entire history. If the file already has &lt;= limit revisions,
    /// nothing is removed.
    /// </para>
    /// <para>
    /// Retained revisions are never rewritten: their RevisionId, contents and
    /// ObjectSerial are untouched, so the next Commit() re-emits them identically.
    /// The head revision is the newest, so it is always retained and the FileHead
    /// record can never be left dangling.
    /// </para>
    /// <para>
    /// Objects are deliberately NOT removed: the object section is a shared content
    /// store that a retained revision elsewhere, or an EXTENTS-1 COPY operand, may
    /// still reference. Reclaiming objects is a separate operation.
    /// </para>
    /// <para>
    /// Returns the removed RevisionIds in ascending order. Idempotent: a repeated
    /// call removes nothing. The change is applied atomically to in-memory state;
    /// persist it with the normal Commit().
    /// </para>
    /// </remarks>
    public List<ulong> LimitCleanUp(byte[] fileId, ulong limit)
    {
        CheckOpen();
        if (limit < 1)
            throw new VsnException(0x000C, $"LimitCleanUp limit must be >= 1, got {limit}");
        if (!_fileIds.ContainsKey(FileKey(fileId)))
            throw new VsnException(0x0009, "unknown FileId");

        // Canonical revision ordering is ascending RevisionId.
        var key = FileKey(fileId);
        var rids = new List<ulong>();
        foreach (var rid in _revisions.Keys)
            if (FileKey(_revisions[rid].FileId) == key) rids.Add(rid);
        rids.Sort();
        if (rids.Count <= (int)limit) return new List<ulong>();   // no state touched

        var removed = rids.GetRange(0, rids.Count - (int)limit);
        if (_fileIds[key].HeadRevision is ulong head && removed.Contains(head))
            throw new VsnException(0x000C,
                $"LimitCleanUp would remove head revision {head}");

        // Apply atomically: snapshot the entries being removed, mutate, and restore
        // them in place on any failure so a failed cleanup never leaves partially
        // pruned history behind. The stores are restored in place because they are
        // readonly fields.
        var snapshot = new Dictionary<ulong, RevisionRecord>();
        foreach (var rid in removed) snapshot[rid] = _revisions[rid];
        var cacheSnapshot = new Dictionary<ulong, byte[]>(_contentCache);
        try
        {
            foreach (var rid in removed) _revisions.Remove(rid);
            _contentCache.Clear();
        }
        catch
        {
            foreach (var kv in snapshot) _revisions[kv.Key] = kv.Value;
            _contentCache.Clear();
            foreach (var kv in cacheSnapshot) _contentCache[kv.Key] = kv.Value;
            throw;
        }
        return removed;
    }

    // --- Object API ---

    private ulong AddObjectInternal(byte[] content)
    {
        ulong serial = _nextObjectSerial++;
        _objects[serial] = Writer.Direct1Descriptor(content);
        return serial;
    }

    public ulong AddObject(byte[] content) => AddObjectInternal(content);

    /// <summary>Register an explicit object descriptor (used for EXTENTS-1/COPY).</summary>
    public ulong AddObjectDescriptor(byte[] descriptor, ulong? serial = null)
    {
        ulong sid = serial ?? _nextObjectSerial++;
        if (sid >= _nextObjectSerial) _nextObjectSerial = sid + 1;
        _objects[sid] = (byte[])descriptor.Clone();
        return sid;
    }

    public List<ulong> ListObjects()
    {
        CheckOpen();
        var result = new List<ulong>(_objects.Keys);
        result.Sort();
        return result;
    }

    public ObjectInfo GetObjectInfo(ulong serial)
    {
        CheckOpen();
        if (!_objects.TryGetValue(serial, out var desc))
            throw new VsnException(0x0008, $"missing object {serial}");
        var (ident, ver, remainder) = Representations.ParseObjectHeader(desc);
        return new ObjectInfo(serial, remainder.Length, ident, ver);
    }

    public ulong? GetObjectSerial(byte[] fileId, ulong? revisionId = null)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        ulong? rid = revisionId ?? info.HeadRevision;
        if (rid == null) return null;
        if (!_revisions.TryGetValue(rid.Value, out var rev)) return null;
        return rev.ObjectSerial;
    }

    public byte[] Materialize(ulong serial, HashSet<ulong>? visited = null)
    {
        visited ??= new HashSet<ulong>();
        if (!visited.Add(serial))
            throw new VsnException(0x000C, $"dependency cycle at ObjectSerial {serial}");
        if (_contentCache.TryGetValue(serial, out var cached))
            return cached;
        if (!_objects.TryGetValue(serial, out var desc))
            throw new VsnException(0x0008, $"missing object {serial}");
        var (ident, ver, remainder) = Representations.ParseObjectHeader(desc);
        byte[] result;
        if (ident == Constants.RepDirect1 && ver == Constants.RepVersion1)
            result = Representations.MaterializeDirect(remainder);
        else if (ident == Constants.RepExtents1 && ver == Constants.RepVersion1)
            result = Representations.MaterializeExtents(remainder,
                s => Materialize(s, new HashSet<ulong>(visited)));
        else
            throw new VsnException(0x0006, $"unsupported representation 0x{ident:X4} v{ver}");
        _contentCache[serial] = result;
        return result;
    }


    // --- Streaming (chunked; never requires the full logical content in memory) ---

    public IEnumerable<byte[]> MaterializeStream(ulong serial, int chunkSize = 65536, HashSet<ulong>? visited = null)
    {
        visited ??= new HashSet<ulong>();
        if (!visited.Add(serial))
            throw new VsnException(0x000C, $"dependency cycle at ObjectSerial {serial}");
        if (!_objects.TryGetValue(serial, out var desc))
            throw new VsnException(0x0008, $"missing object {serial}");
        var (ident, ver, remainder) = Representations.ParseObjectHeader(desc);
        if (ident == Constants.RepDirect1 && ver == Constants.RepVersion1)
        {
            var bytes = remainder.ToArray();
            for (int i = 0; i < bytes.Length; i += chunkSize)
                yield return bytes[i..Math.Min(i + chunkSize, bytes.Length)];
            yield break;
        }
        if (ident == Constants.RepExtents1 && ver == Constants.RepVersion1)
        {
            var next = new HashSet<ulong>(visited);
            foreach (var chunk in Representations.MaterializeExtentsStream(remainder,
                s => Materialize(s, new HashSet<ulong>(next)), chunkSize))
                yield return chunk;
            yield break;
        }
        throw new VsnException(0x0006, $"unsupported representation 0x{ident:X4} v{ver}");
    }

    public IEnumerable<byte[]> ReadFileStream(byte[] fileId, int chunkSize = 65536)
    {
        CheckOpen();
        if (!_fileIds.TryGetValue(FileKey(fileId), out var info))
            throw new VsnException(0x0009, "unknown FileId");
        if (info.HeadRevision == null)
            throw new VsnException(0x0009, "no accepted revision");
        var rev = _revisions[info.HeadRevision.Value];
        if (rev.Presence == Constants.Deleted)
            throw new VsnException(0x0009, "file is deleted");
        if (rev.ObjectSerial == null) yield break;
        foreach (var chunk in MaterializeStream(rev.ObjectSerial.Value, chunkSize))
            yield return chunk;
    }

    // --- Canonical serialization ---

    /// <summary>Produce canonical VSN-1 bytes from current state (SR-* closure).</summary>
    public byte[] ToBytes()
    {
        CheckOpen();
        _generation += 1;
        var records = new List<(ushort, List<(ushort, byte[])>)>
        {
            (Constants.RecModeDeclaration,
                new List<(ushort, byte[])> { (Constants.FidMode, new[] { _mode }) }),
        };
        foreach (var info in _fileIds.Values)
            records.Add((Constants.RecFileIdentity,
                new List<(ushort, byte[])> { (Constants.FidFileId, info.FileId) }));
        var rids = new List<ulong>(_revisions.Keys);
        rids.Sort();
        foreach (var rid in rids)
        {
            var rev = _revisions[rid];
            var fields = new List<(ushort, byte[])>
            {
                (Constants.FidRevId, Primitives.PutUvarint(rev.RevisionId)),
                (Constants.FidRevFileId, rev.FileId),
            };
            if (rev.ObjectSerial.HasValue)
                fields.Add((Constants.FidRevObjectSerial, Primitives.PutUvarint(rev.ObjectSerial.Value)));
            if (rev.Path != null)
                fields.Add((Constants.FidRevPath, System.Text.Encoding.UTF8.GetBytes(rev.Path)));
            fields.Add((Constants.FidRevPresence, new[] { rev.Presence }));
            records.Add((Constants.RecRevision, fields));
        }
        var serials = new List<ulong>(_objects.Keys);
        serials.Sort();
        foreach (var serial in serials)
        {
            // 0x0511 declared size is the LOGICAL content length (SR-27, DR-6),
            // never the representation payload length. Frozen vector EXT-02/EXT-03
            // is authoritative: serial 20 has a 17-byte EXTENTS-1 remainder but
            // declares size 12 (its materialized length).
            // The field is OPTIONAL (SR-27), so it is omitted when the logical
            // length cannot be resolved (missing dependency, cycle, or an
            // unsupported representation, which is not an invalid state).
            var fields = new List<(ushort, byte[])>
            {
                (Constants.FidObjectSerial, Primitives.PutUvarint(serial)),
            };
            try
            {
                fields.Add((Constants.FidObjectSize,
                    Primitives.PutUvarint((ulong)Materialize(serial).Length)));
            }
            catch (VsnException)
            {
                // Unresolvable object: 0x0511 omitted, which is fully valid.
            }
            records.Add((Constants.RecContentObject, fields));
        }
        foreach (var info in _fileIds.Values)
        {
            if (info.HeadRevision.HasValue)
                records.Add((Constants.RecFileHead,
                    new List<(ushort, byte[])>
                    {
                        (Constants.FidHeadFileId, info.FileId),
                        (Constants.FidHeadRevId, Primitives.PutUvarint(info.HeadRevision.Value)),
                    }));
        }
        records.Add((Constants.RecCommitMarker,
            new List<(ushort, byte[])> { (Constants.FidCommitGeneration, Primitives.PutUvarint(_generation)) }));
        var objects = serials.ConvertAll(s => (s, _objects[s]));
        return Writer.Encode(_mode, records, objects, _generation);
    }

    /// <summary>Commit current state; CommitMarker is the sole acceptance authority.</summary>
    public byte[] Commit()
    {
        CheckOpen();
        var data = ToBytes();
        _data = data;
        _parsed = ContainerParser.Parse(data);
        _contentCache.Clear();
        return data;
    }
}

