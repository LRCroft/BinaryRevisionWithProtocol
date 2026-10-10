namespace Vsn;

/// <summary>A single staged change within a transaction.</summary>
public sealed class StagedChange
{
    public string Operation { get; } // "create", "update", "delete", "rename"
    public byte[]? FileId { get; }
    public string? Path { get; }
    public byte[]? Content { get; }
    public string? NewPath { get; }

    public StagedChange(string operation, byte[]? fileId = null,
        string? path = null, byte[]? content = null, string? newPath = null)
    {
        Operation = operation;
        FileId = fileId;
        Path = path;
        Content = content;
        NewPath = newPath;
    }
}

/// <summary>
/// Transaction with staging, precondition, and commit.
/// ExpectedRevisionId is a precondition ONLY and is NEVER persisted as
/// canonical state (RC-01). The CommitMarker is the sole acceptance authority.
/// </summary>
public sealed class Transaction
{
    public ulong? ExpectedRevisionId { get; }
    private readonly List<StagedChange> _staged = new();
    private bool _committed;

    public Transaction(ulong? expectedRevisionId = null)
    {
        ExpectedRevisionId = expectedRevisionId;
    }

    public void StageCreate(string path, byte[]? content = null) =>
        _staged.Add(new StagedChange("create", path: path, content: content ?? Array.Empty<byte>()));

    public void StageUpdate(byte[] fileId, byte[] content) =>
        _staged.Add(new StagedChange("update", fileId: fileId, content: content));

    public void StageDelete(byte[] fileId) =>
        _staged.Add(new StagedChange("delete", fileId: fileId));

    public void StageRename(byte[] fileId, string newPath) =>
        _staged.Add(new StagedChange("rename", fileId: fileId, newPath: newPath));

    /// <summary>Inspect staged changes (does not touch canonical state).</summary>
    public IReadOnlyList<StagedChange> Inspect() => _staged.AsReadOnly();

    public int ChangeCount => _staged.Count;

    /// <summary>Discard all staged changes.</summary>
    public void Rollback() => _staged.Clear();

    /// <summary>Apply staged changes and commit; returns canonical bytes.</summary>
    public byte[] Commit(VsnStore store)
    {
        if (_committed)
            throw new VsnException(0x000C, "transaction already committed");
        if (ExpectedRevisionId.HasValue)
        {
            foreach (var change in _staged)
            {
                if (change.FileId == null) continue;
                var current = store.GetCurrentRevision(change.FileId);
                if (current != ExpectedRevisionId.Value)
                    throw new VsnException(0x000D,
                        $"ExpectedRevisionId mismatch: expected {ExpectedRevisionId.Value}, got {current?.ToString() ?? "null"}");
                break;
            }
        }
        foreach (var change in _staged)
        {
            switch (change.Operation)
            {
                case "create": store.CreateFile(change.Path!, change.Content ?? Array.Empty<byte>()); break;
                case "update": store.WriteFile(change.FileId!, change.Content!); break;
                case "delete": store.DeleteFile(change.FileId!); break;
                case "rename": store.RenameFile(change.FileId!, change.NewPath!); break;
            }
        }
        _committed = true;
        return store.Commit();
    }
}
