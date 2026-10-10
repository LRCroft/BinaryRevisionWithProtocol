namespace Vsn;

/// <summary>Object-set difference (derived data; never canonical).</summary>
public sealed class ObjectDiff
{
    public List<ulong> Shared { get; } = new();
    public List<ulong> Added { get; } = new();
    public List<ulong> Removed { get; } = new();
}

/// <summary>File-state difference between two stores.</summary>
public sealed class FileDiff
{
    public List<string> Added { get; } = new();
    public List<string> Deleted { get; } = new();
    public List<string> Modified { get; } = new();
    public List<string> Unchanged { get; } = new();
    public List<(string oldPath, string newPath)> Renamed { get; } = new();
}

/// <summary>Revision content difference.</summary>
public sealed class RevisionDiff
{
    public ulong RevisionA { get; init; }
    public ulong RevisionB { get; init; }
    public byte[] ContentA { get; init; } = Array.Empty<byte>();
    public byte[] ContentB { get; init; } = Array.Empty<byte>();
    public bool Changed { get; init; }
    public long AddedBytes { get; init; }
}

/// <summary>VSN library-level diff (derived, never canonical).</summary>
public static class Diff
{
    public static ObjectDiff DiffObjects(IEnumerable<ulong> left, IEnumerable<ulong> right)
    {
        var l = new HashSet<ulong>(left);
        var r = new HashSet<ulong>(right);
        var d = new ObjectDiff();
        d.Shared.AddRange(l.Intersect(r).OrderBy(x => x));
        d.Added.AddRange(r.Except(l).OrderBy(x => x));
        d.Removed.AddRange(l.Except(r).OrderBy(x => x));
        return d;
    }

    public static FileDiff DiffFiles(VsnStore left, VsnStore right)
    {
        var leftFiles = left.ListFiles().Where(f => f.Path != null)
            .ToDictionary(f => f.Path!, f => f.FileId);
        var rightFiles = right.ListFiles().Where(f => f.Path != null)
            .ToDictionary(f => f.Path!, f => f.FileId);
        var result = new FileDiff();
        foreach (var path in leftFiles.Keys.Union(rightFiles.Keys).OrderBy(p => p))
        {
            bool inLeft = leftFiles.ContainsKey(path);
            bool inRight = rightFiles.ContainsKey(path);
            if (inLeft && !inRight) result.Deleted.Add(path);
            else if (inRight && !inLeft) result.Added.Add(path);
            else if (left.ReadFile(leftFiles[path]).SequenceEqual(right.ReadFile(rightFiles[path])))
                result.Unchanged.Add(path);
            else result.Modified.Add(path);
        }
        return result;
    }

    public static RevisionDiff DiffRevisions(VsnStore store, byte[] fileId, ulong revA, ulong revB)
    {
        var a = store.CheckoutRevision(fileId, revA);
        var b = store.CheckoutRevision(fileId, revB);
        bool changed = !a.SequenceEqual(b);
        return new RevisionDiff
        {
            RevisionA = revA, RevisionB = revB, ContentA = a, ContentB = b,
            Changed = changed, AddedBytes = changed ? (long)b.Length - a.Length : 0,
        };
    }
}

