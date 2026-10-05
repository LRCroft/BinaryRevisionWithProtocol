namespace Vsn;

/// <summary>
/// VSN-1 canonical writer (encoder).
/// Produces canonical VSN-1 bytes. Only frozen record types, field IDs, and
/// representations are emitted. Identity is never derived from hash or offset.
/// </summary>
public static class Writer
{
    private static byte[] Field(ushort fid, byte[] value)
    {
        var result = new List<byte>();
        result.AddRange(Primitives.PutU16(fid));
        result.AddRange(Primitives.PutUvarint((ulong)value.Length));
        result.AddRange(value);
        return result.ToArray();
    }

    private static byte[] Record(ushort rtype, List<(ushort fid, byte[] value)> fields)
    {
        var payload = new List<byte>();
        foreach (var (fid, val) in fields)
            payload.AddRange(Field(fid, val));
        var result = new List<byte>();
        result.AddRange(Primitives.PutU16(rtype));
        result.AddRange(Primitives.PutUvarint((ulong)payload.Count));
        result.AddRange(payload);
        return result.ToArray();
    }

    /// <summary>Encode a canonical container.</summary>
    public static byte[] Encode(byte mode, List<(ushort rtype, List<(ushort fid, byte[] value)> fields)> records,
        List<(ulong serial, byte[] descriptor)> objects, ulong generation)
    {
        var result = new List<byte>();
        result.AddRange(Constants.Magic);
        result.AddRange(Primitives.PutU16(1)); // ContainerFormatVersion
        result.AddRange(Primitives.PutU16(1)); // EncodingVersion
        result.AddRange(Field(Constants.FidRecordsEnd, Array.Empty<byte>())); // RecordsEnd

        foreach (var (rtype, fields) in records)
            result.AddRange(Record(rtype, fields));
        result.AddRange(Primitives.PutU16(Constants.RecEndOfRecords)); // end-of-records

        foreach (var (serial, descriptor) in objects)
        {
            result.AddRange(Primitives.PutUvarint(serial));
            result.AddRange(Primitives.PutUvarint((ulong)descriptor.Length));
            result.AddRange(descriptor);
        }
        result.AddRange(Primitives.PutUvarint(0)); // end-of-objects

        // GR-13: canonical record count excludes ModeDeclaration
        ulong canonicalCount = 0;
        foreach (var (rtype, _) in records)
            if (rtype != Constants.RecModeDeclaration)
                canonicalCount++;
        result.AddRange(Primitives.PutUvarint(canonicalCount));
        result.AddRange(Primitives.PutUvarint(generation));
        return result.ToArray();
    }

    /// <summary>Create a DIRECT-1 object descriptor (DR-0 header + content).</summary>
    public static byte[] Direct1Descriptor(byte[] content)
    {
        var result = new List<byte>();
        result.AddRange(Primitives.PutU16(Constants.RepDirect1));
        result.AddRange(Primitives.PutUvarint(Constants.RepVersion1));
        result.AddRange(content);
        return result.ToArray();
    }

    /// <summary>LITERAL operation: NESTED[ LITERAL_BYTES(bytes), NUMERIC(0) ].</summary>
    public static byte[] LiteralOperation(byte[] content)
    {
        var result = new List<byte>();
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpNested));
        result.AddRange(Primitives.PutUvarint(2));
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpLiteralBytes));
        result.AddRange(Primitives.PutUvarint((ulong)content.Length));
        result.AddRange(content);
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpNumeric));
        result.AddRange(Primitives.PutUvarint(0));
        return result.ToArray();
    }

    /// <summary>COPY operation: NESTED[ OBJECT_SOURCE(serial), NUMERIC(off), NUMERIC(len) ].</summary>
    public static byte[] CopyOperation(ulong serial, ulong offset, ulong length)
    {
        var result = new List<byte>();
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpNested));
        result.AddRange(Primitives.PutUvarint(3));
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpObjectSource));
        result.AddRange(Primitives.PutUvarint(serial));
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpNumeric));
        result.AddRange(Primitives.PutUvarint(offset));
        result.AddRange(Primitives.PutUvarint((ulong)Constants.OpNumeric));
        result.AddRange(Primitives.PutUvarint(length));
        return result.ToArray();
    }

    /// <summary>EXTENTS-1 descriptor: header + operation collection.</summary>
    public static byte[] Extents1Descriptor(List<byte[]> operations)
    {
        var result = new List<byte>();
        result.AddRange(Primitives.PutU16(Constants.RepExtents1));
        result.AddRange(Primitives.PutUvarint(Constants.RepVersion1));
        result.AddRange(Primitives.PutUvarint((ulong)operations.Count));
        foreach (var op in operations)
            result.AddRange(op);
        return result.ToArray();
    }
}
