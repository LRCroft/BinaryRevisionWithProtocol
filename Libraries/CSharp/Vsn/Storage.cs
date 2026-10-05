namespace Vsn;

/// <summary>Storage statistics for a container (derived observation).</summary>
public sealed class StorageStats
{
    public int ContainerBytes { get; init; }
    public int RecordCount { get; init; }
    public int ObjectCount { get; init; }
    public int FileCount { get; init; }
    public int RevisionCount { get; init; }
    public int IndexEntries { get; init; }
    public int CacheEntries { get; init; }
    public long CacheBytes { get; init; }
}

/// <summary>
/// Manages derived storage (indexes, caches) for a VsnStore.
/// All derived data is rebuildable from canonical VSN content. Recovery and
/// acceptance never depend on it (SR-02, SR-03); it is never canonical
/// authority. Deleting every derived structure leaves recovery functional.
/// </summary>
public sealed class StorageManager
{
    private readonly Dictionary<ulong, ObjectInfo> _objectIndex = new();
    private readonly Dictionary<string, byte[]> _fileIndex = new(StringComparer.Ordinal);
    private readonly Dictionary<ulong, byte[]> _contentCache = new();

    public bool IsValid { get; private set; }

    /// <summary>Build derived indexes from canonical state.</summary>
    public void BuildIndexes(VsnStore store)
    {
        _objectIndex.Clear();
        _fileIndex.Clear();
        foreach (var serial in store.ListObjects())
            _objectIndex[serial] = store.GetObjectInfo(serial);
        foreach (var info in store.ListFiles())
            if (info.Path != null) _fileIndex[info.Path] = info.FileId;
        IsValid = true;
    }

    /// <summary>Invalidate all derived data (simulates derived-store deletion).</summary>
    public void Invalidate()
    {
        _objectIndex.Clear();
        _fileIndex.Clear();
        _contentCache.Clear();
        IsValid = false;
    }

    /// <summary>Rebuild derived data from canonical state.</summary>
    public void Rebuild(VsnStore store)
    {
        Invalidate();
        BuildIndexes(store);
    }

    /// <summary>Garbage-collect cached content; returns entries removed.</summary>
    public int Gc()
    {
        int n = _contentCache.Count;
        _contentCache.Clear();
        return n;
    }

    public void CachePut(ulong serial, byte[] content) => _contentCache[serial] = content;
    public byte[]? CacheGet(ulong serial) => _contentCache.TryGetValue(serial, out var v) ? v : null;
    public int CacheCount => _contentCache.Count;
    public byte[]? LookupFile(string path) => _fileIndex.TryGetValue(path, out var v) ? v : null;

    /// <summary>Storage statistics.</summary>
    public StorageStats Stats(VsnStore store) => new()
    {
        ContainerBytes = store.CanonicalData.Length,
        RecordCount = store.Parsed?.Records.Count ?? 0,
        ObjectCount = store.ListObjects().Count,
        FileCount = store.ListFiles().Count,
        RevisionCount = store.ListRevisions().Count,
        IndexEntries = _objectIndex.Count + _fileIndex.Count,
        CacheEntries = _contentCache.Count,
        CacheBytes = _contentCache.Values.Sum(v => (long)v.Length),
    };
}
