namespace Vsn;

/// <summary>VSN validation layers: Structural, Semantic, Recovery, Content, Full.</summary>
public static class Validate
{
    public static void Structural(ReadOnlyMemory<byte> data) => ContainerParser.Parse(data);

    public static void Semantic(ReadOnlyMemory<byte> data)
    {
        var parsed = ContainerParser.Parse(data);
        CheckMode(parsed);
        CheckIdentities(parsed);
        CheckReferences(parsed);
    }

    private static void CheckMode(ParsedContainer parsed)
    {
        var modes = parsed.Records.Where(r => r.RType == Constants.RecModeDeclaration).ToList();
        var spRecords = parsed.Records.Where(r => r.RType == Constants.RecStoragePolicy).ToList();
        
        byte modeToCheck;
        if (spRecords.Count >= 1)
        {
            // Canonical path: derive wire mode from storage policy
            byte? spVal = null;
            foreach (var spRec in spRecords)
            {
                var spField = spRec.GetField(Constants.FidStoragePolicy);
                if (spField != null && spField.Value.Length >= 1)
                {
                    spVal = spField.Value.Span[0];
                    break;
                }
            }
            if (spVal == null)
                throw new VsnException(0x000C, "REC_STORAGE_POLICY missing storage_policy value");
            if (spVal < 1 || spVal > 4)
                throw new VsnException(0x0001, $"invalid storage policy {spVal}");
            // Vertical policies (1,2) -> MODERN; Horizontal (3,4) -> ENTERPRISE
            modeToCheck = (spVal >= 3) ? Constants.ModeEnterprise : Constants.ModeModern;
        }
        else if (modes.Count == 1)
        {
            var m = modes[0].GetField(Constants.FidMode);
            if (m == null || m.Value.Length != 1)
                throw new VsnException(0x000C, "ModeDeclaration missing mode value");
            modeToCheck = m.Value.Span[0];
        }
        else
        {
            throw new VsnException(0x000C, "expected exactly one ModeDeclaration or REC_STORAGE_POLICY");
        }
        
        if (modeToCheck != Constants.ModeModern && modeToCheck != Constants.ModeEnterprise)
            throw new VsnException(0x0001, $"reserved mode value 0x{modeToCheck:X2}");
        // GR-43: ENTERPRISE must not use EXTENTS-1 reconstruction semantics.
        if (modeToCheck == Constants.ModeEnterprise)
        {
            foreach (var obj in parsed.Objects)
            {
                var (ident, _, _) = Representations.ParseObjectHeader(obj.Descriptor);
                if (ident == Constants.RepExtents1)
                    throw new VsnException(0x000C, "ENTERPRISE mode forbids EXTENTS-1 (GR-43)");
            }
        }
    }

    private static void CheckIdentities(ParsedContainer parsed)
    {
        var seenFile = new HashSet<string>(StringComparer.Ordinal);
        var seenRev = new HashSet<ulong>();
        var seenObj = new HashSet<ulong>();
        foreach (var rec in parsed.Records)
        {
            if (rec.RType == Constants.RecFileIdentity)
            {
                var f = rec.GetField(Constants.FidFileId);
                var key = f == null ? "null" : Convert.ToHexString(f.Value.Span);
                if (!seenFile.Add(key))
                    throw new VsnException(0x000A, "duplicate FileIdentity");
            }
            else if (rec.RType == Constants.RecRevision)
            {
                var r = rec.GetField(Constants.FidRevId);
                if (r != null && !seenRev.Add(r.AsUvarint()))
                    throw new VsnException(0x000A, $"duplicate RevisionId {r.AsUvarint()}");
            }
            else if (rec.RType == Constants.RecContentObject)
            {
                var s = rec.GetField(Constants.FidObjectSerial);
                if (s != null && !seenObj.Add(s.AsUvarint()))
                    throw new VsnException(0x000A, $"duplicate ObjectSerial {s.AsUvarint()}");
            }
        }
    }

    private static void CheckReferences(ParsedContainer parsed)
    {
        var fileIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var r in parsed.Records)
        {
            if (r.RType != Constants.RecFileIdentity) continue;
            var f = r.GetField(Constants.FidFileId);
            if (f != null) fileIds.Add(Convert.ToHexString(f.Value.Span));
        }
        var objIds = new HashSet<ulong>(parsed.Objects.Select(o => o.Serial.Value));
        var revIds = new HashSet<ulong>();
        foreach (var r in parsed.Records)
        {
            if (r.RType != Constants.RecRevision) continue;
            var rr = r.GetField(Constants.FidRevId);
            if (rr != null) revIds.Add(rr.AsUvarint());
        }
        foreach (var rec in parsed.Records)
        {
            if (rec.RType == Constants.RecRevision)
            {
                var f = rec.GetField(Constants.FidRevFileId);
                if (f == null || !fileIds.Contains(Convert.ToHexString(f.Value.Span)))
                    throw new VsnException(0x0009, "Revision references missing FileId");
                var obj = rec.GetField(Constants.FidRevObjectSerial);
                if (obj != null && !objIds.Contains(obj.AsUvarint()))
                    throw new VsnException(0x0008, "Revision references missing ObjectSerial");
            }
            else if (rec.RType == Constants.RecFileHead)
            {
                var f = rec.GetField(Constants.FidHeadFileId);
                if (f == null || !fileIds.Contains(Convert.ToHexString(f.Value.Span)))
                    throw new VsnException(0x0009, "FileHead references missing FileId");
                var r = rec.GetField(Constants.FidHeadRevId);
                if (r == null || !revIds.Contains(r.AsUvarint()))
                    throw new VsnException(0x0009, "FileHead references missing RevisionId");
            }
        }
    }

    /// <summary>Content: every object must materialize (dependency validation + cycles).</summary>
    /// <remarks>
    /// DR-6 additionally requires that when 0x0511 is PRESENT, the materialized
    /// output length MUST equal it; a mismatch is invalid canonical state (0x000C,
    /// matching frozen vector EXT-12). Absence of 0x0511 stays fully valid (SR-27).
    /// Reuses the existing INVALID_CANONICAL_STATE identifier; no new identifier
    /// is introduced, and no derived storage is consulted.
    /// </remarks>
    public static void Content(ReadOnlyMemory<byte> data)
    {
        var parsed = ContainerParser.Parse(data);
        var declared = new Dictionary<ulong, ulong>();
        foreach (var rec in parsed.Records)
        {
            if (rec.RType != Constants.RecContentObject) continue;
            var s = rec.GetField(Constants.FidObjectSerial);
            var z = rec.GetField(Constants.FidObjectSize);
            if (s != null && z != null) declared[s.AsUvarint()] = z.AsUvarint();
        }

        var c = VsnContainer.Open(data);
        foreach (var obj in c.Objects)
        {
            var content = c.Materialize(obj.Serial.Value);
            if (declared.TryGetValue(obj.Serial.Value, out var want)
                && want != (ulong)content.Length)
                throw new VsnException(0x000C,
                    $"declared size {want} does not match materialized length " +
                    $"{content.Length} for ObjectSerial {obj.Serial.Value} (DR-6)");
        }
    }

    /// <summary>Run validation at a requested depth.</summary>
    public static void Run(ReadOnlyMemory<byte> data, string level = "Full")
    {
        var levels = new[] { "Structural", "Semantic", "Recovery", "Content", "Full" };
        if (!levels.Contains(level))
            throw new ArgumentException($"unknown validation level {level}");
        if (level == "Structural" || level == "Full") Structural(data);
        if (level == "Semantic" || level == "Full") Semantic(data);
        if (level == "Recovery" || level == "Full") Recovery.Recover(data);
        if (level == "Content" || level == "Full") Content(data);
    }
}

