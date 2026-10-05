namespace Vsn;

/// <summary>Diagnostic severity (library vocabulary, not a protocol identifier).</summary>
public enum Severity { Error, Warning, Info }

/// <summary>Diagnostic category: frozen protocol error vs library-only vs derived data.</summary>
public enum Category { Protocol, Library, Derived }

/// <summary>Structured diagnostic carrying full context.</summary>
public sealed class Diagnostic
{
    public int Code { get; init; }
    public string Name { get; init; } = "";
    public Severity Severity { get; init; }
    public Category Category { get; init; }
    public string Message { get; init; } = "";
    public int? ByteOffset { get; init; }
    public int? RecordType { get; init; }
    public int? FieldId { get; init; }
    public ulong? ObjectSerial { get; init; }
    public byte[]? FileId { get; init; }
    public ulong? RevisionId { get; init; }
    public int? RepIdentity { get; init; }
    public int? RepVersion { get; init; }
    public string? Operation { get; init; }
    public Exception? Cause { get; init; }

    public static Diagnostic FromVsnError(VsnException e, string? operation = null) => new()
    {
        Code = e.Code,
        Name = e.Name,
        Severity = Severity.Error,
        Category = Category.Protocol,
        Message = e.Message,
        ByteOffset = e.ByteOffset,
        Operation = operation,
        Cause = e,
    };

    public static Diagnostic LibraryError(string name, string message, string? operation = null, Exception? cause = null) => new()
    {
        Code = -1,
        Name = name,
        Severity = Severity.Error,
        Category = Category.Library,
        Message = message,
        Operation = operation,
        Cause = cause,
    };

    /// <summary>Run validation and return diagnostics instead of throwing.</summary>
    public static List<Diagnostic> ValidateWithDiagnostics(ReadOnlyMemory<byte> data, string level = "Full")
    {
        var diags = new List<Diagnostic>();
        foreach (var lvl in ValidationLevels(level))
        {
            try
            {
                if (lvl == "Structural") Validate.Structural(data);
                else if (lvl == "Semantic") Validate.Semantic(data);
                else if (lvl == "Recovery") Recovery.Recover(data);
                else if (lvl == "Content") Validate.Content(data);
            }
            catch (VsnException ex)
            {
                diags.Add(FromVsnError(ex, lvl));
                break;
            }
            catch (Exception ex)
            {
                diags.Add(LibraryError("LIBRARY_ERROR", ex.Message, lvl, ex));
                break;
            }
        }
        return diags;
    }

    private static List<string> ValidationLevels(string level) => level switch
    {
        "Structural" => new() { "Structural" },
        "Semantic" => new() { "Structural", "Semantic" },
        "Recovery" => new() { "Structural", "Semantic", "Recovery" },
        "Content" => new() { "Structural", "Semantic", "Content" },
        "Full" => new() { "Structural", "Semantic", "Recovery", "Content" },
        _ => throw new ArgumentException($"unknown validation level {level}"),
    };
}
