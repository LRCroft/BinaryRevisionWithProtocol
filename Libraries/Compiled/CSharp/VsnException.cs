namespace Vsn;

/// <summary>
/// VSN exception carrying a frozen error identifier (VR-28, VR-29).
/// </summary>
public class VsnException : Exception
{
    public int Code { get; }
    public string Name { get; }
    public int? ByteOffset { get; }

    public VsnException(int code, string message, int? byteOffset = null)
        : base(message)
    {
        Code = code;
        Name = ErrorRegistry.GetName(code);
        ByteOffset = byteOffset;
    }

    public override string ToString() => $"VsnException({Name}: {Message})";
}

/// <summary>Frozen error registry (VR-28, VR-29).</summary>
public static class ErrorRegistry
{
    private static readonly Dictionary<int, string> Names = new()
    {
        [0x0000] = "OK",
        [0x0001] = "MALFORMED_CONTAINER",
        [0x0002] = "TRUNCATED",
        [0x0003] = "UNSUPPORTED_CONTAINER_VERSION",
        [0x0004] = "UNSUPPORTED_ENCODING_VERSION",
        [0x0005] = "UNSUPPORTED_PROTOCOL_VERSION",
        [0x0006] = "UNSUPPORTED_REPRESENTATION",
        [0x0007] = "UNSUPPORTED_TRANSFORM",
        [0x0008] = "MISSING_OBJECT",
        [0x0009] = "MISSING_CANONICAL_REFERENCE",
        [0x000A] = "DUPLICATE_IDENTITY",
        [0x000B] = "INVALID_RELATIONSHIP",
        [0x000C] = "INVALID_CANONICAL_STATE",
        [0x000D] = "VERIFICATION_UNAVAILABLE",
        [0x000E] = "VERIFICATION_MISMATCH",
        [0x000F] = "INVALID_UTF8",
        [0x0010] = "RESERVED_VALUE",
        [0x0011] = "INVALID_FIELD_ORDERING",
        [0x0012] = "INVALID_LENGTH",
        [0x0013] = "UNKNOWN_MANDATORY_RECORD",
        [0x0014] = "ACCESS_OR_DECRYPTION_FAILURE",
    };

    public static string GetName(int code) => Names.TryGetValue(code, out var name) ? name : "UNKNOWN";
}

