namespace Vsn;

/// <summary>A three-way merge conflict.</summary>
public sealed class Conflict
{
    public string Path { get; }
    public byte[] BaseContent { get; }
    public byte[] OursContent { get; }
    public byte[] TheirsContent { get; }

    public Conflict(string path, byte[] baseContent, byte[] oursContent, byte[] theirsContent)
    {
        Path = path;
        BaseContent = baseContent;
        OursContent = oursContent;
        TheirsContent = theirsContent;
    }
}

/// <summary>Result of a three-way merge (library state only; no protocol records).</summary>
public sealed class MergeResult
{
    public Dictionary<string, byte[]> MergedFiles { get; } = new();
    public List<Conflict> Conflicts { get; set; } = new();
    public List<string> Added { get; } = new();
    public List<string> Deleted { get; } = new();
    public bool HasConflicts => Conflicts.Count > 0;
}

/// <summary>
/// Three-way merge of file states. Conflicting changes are reported and never
/// silently dropped (no silent data loss).
/// </summary>
public static class Merge
{
    private static Dictionary<string, byte[]> FilesByPath(VsnStore store)
    {
        var map = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var f in store.ListFiles())
            if (f.Path != null) map[f.Path] = f.FileId;
        return map;
    }

    public static MergeResult ThreeWayMerge(VsnStore baseStore, VsnStore ours, VsnStore theirs)
    {
        var baseFiles = FilesByPath(baseStore);
        var oursFiles = FilesByPath(ours);
        var theirsFiles = FilesByPath(theirs);
        var result = new MergeResult();
        bool Eq(byte[]? a, byte[]? b) =>
            a == null ? b == null : b != null && a.SequenceEqual(b);

        foreach (var path in baseFiles.Keys.Union(oursFiles.Keys).Union(theirsFiles.Keys).OrderBy(p => p))
        {
            byte[]? baseC = baseFiles.TryGetValue(path, out var bf) ? baseStore.ReadFile(bf) : null;
            byte[]? oursC = oursFiles.TryGetValue(path, out var of_) ? ours.ReadFile(of_) : null;
            byte[]? theirsC = theirsFiles.TryGetValue(path, out var tf) ? theirs.ReadFile(tf) : null;

            if (Eq(oursC, theirsC))
            {
                if (oursC != null) result.MergedFiles[path] = oursC;
                continue;
            }
            if (Eq(oursC, baseC) && !Eq(theirsC, baseC))
            {
                if (theirsC != null) result.MergedFiles[path] = theirsC;
                else result.Deleted.Add(path);
                continue;
            }
            if (Eq(theirsC, baseC) && !Eq(oursC, baseC))
            {
                if (oursC != null) result.MergedFiles[path] = oursC;
                else result.Deleted.Add(path);
                continue;
            }
            result.Conflicts.Add(new Conflict(path,
                baseC ?? Array.Empty<byte>(), oursC ?? Array.Empty<byte>(), theirsC ?? Array.Empty<byte>()));
        }
        return result;
    }

    /// <summary>Resolve a conflict explicitly by supplying the final content.</summary>
    public static void ResolveConflict(MergeResult result, string path, byte[] content)
    {
        result.Conflicts = result.Conflicts.Where(c => c.Path != path).ToList();
        result.MergedFiles[path] = content;
    }
}
