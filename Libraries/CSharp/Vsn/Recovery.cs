namespace Vsn;

/// <summary>Recovery outcome of marker-based recovery (RC-01..RC-45).</summary>
public sealed class RecoveryResult
{
    public ulong AcceptedGeneration { get; }
    public bool Recovered { get; }
    public bool TailPresent { get; }
    public string Status { get; }
    public string Message { get; }

    public RecoveryResult(ulong generation, bool recovered, bool tail, string status, string message)
    {
        AcceptedGeneration = generation;
        Recovered = recovered;
        TailPresent = tail;
        Status = status;
        Message = message;
    }
}

/// <summary>
/// Marker-based recovery: accepted state is the canonical data preceding the
/// highest-Generation structurally complete and semantically valid
/// CommitMarker. No index, cache, checkpoint, or heuristic substitutes.
/// </summary>
public static class Recovery
{
    public static RecoveryResult Recover(ReadOnlyMemory<byte> data)
    {
        ParsedContainer parsed;
        try
        {
            parsed = ContainerParser.Parse(data);
        }
        catch (VsnException ex) when (ex.Code == 0x0002)
        {
            return new RecoveryResult(0, false, true, "TRUNCATED", "physical end reached mid-unit");
        }
        catch (VsnException ex)
        {
            return new RecoveryResult(0, false, false, "MALFORMED", ex.Message);
        }

        var markers = new List<ulong>();
        foreach (var rec in parsed.Records)
        {
            if (rec.RType != Constants.RecCommitMarker) continue;
            var g = rec.GetField(Constants.FidCommitGeneration);
            if (g != null) markers.Add(g.AsUvarint());
        }
        if (markers.Count == 0)
            return new RecoveryResult(0, false, false, "NO_MARKER", "no CommitMarker present");

        ulong gen = markers.Max();
        bool tail = parsed.TrailerGeneration != 0 && parsed.TrailerGeneration != gen;
        return new RecoveryResult(gen, true, tail, "RECOVERED", $"accepted generation {gen}");
    }
}
