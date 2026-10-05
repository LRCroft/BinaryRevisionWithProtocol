namespace Vsn;

using System.Security.Cryptography;

/// <summary>Integrity report over the canonical state.</summary>
public sealed class IntegrityReport
{
    public bool Valid { get; init; }
    public byte Mode { get; init; }
    public ulong Generation { get; init; }
    public int FileCount { get; init; }
    public int ObjectCount { get; init; }
    public int RevisionCount { get; init; }
    public string ContentHash { get; init; } = "";
    public List<string> Errors { get; init; } = new();
}

/// <summary>
/// Library-level integrity verification over the canonical state.
/// Hashes are verification/acceleration mechanisms ONLY; they are never
/// canonical identity and never recovery authority (BP-09, SR-40).
/// </summary>
public static class Integrity
{
    /// <summary>Hash the canonical bytes (verification only, never identity).</summary>
    public static string CanonicalHash(byte[] data) =>
        Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();

    /// <summary>Verify a store: Full validation plus every accepted file materializes.</summary>
    public static IntegrityReport VerifyIntegrity(VsnStore store)
    {
        var errors = new List<string>();
        var data = store.CanonicalData.Length > 0 ? store.CanonicalData : store.ToBytes();
        try
        {
            Validate.Run(data, "Full");
        }
        catch (Exception ex)
        {
            errors.Add(ex.Message);
        }
        foreach (var info in store.ListFiles())
        {
            if (!store.FileExists(info.FileId)) continue;
            try
            {
                store.ReadFile(info.FileId);
            }
            catch (Exception ex)
            {
                errors.Add($"{info.Path}: {ex.Message}");
            }
        }
        var meta = store.Inspect();
        return new IntegrityReport
        {
            Valid = errors.Count == 0,
            Mode = meta.Mode,
            Generation = meta.Generation,
            FileCount = meta.FileCount,
            ObjectCount = meta.ObjectCount,
            RevisionCount = meta.RevisionCount,
            ContentHash = CanonicalHash(data),
            Errors = errors,
        };
    }
}
