namespace Vsn;

/// <summary>
/// VSN-1 representation materialization: DIRECT-1 and EXTENTS-1 (DR-0..DR-12).
/// </summary>
public static class Representations
{
    /// <summary>Parse the DR-0 object header: (identity, version, remainder).</summary>
    public static (ushort identity, int version, ReadOnlyMemory<byte> remainder) ParseObjectHeader(ReadOnlyMemory<byte> descriptor)
    {
        var span = descriptor.Span;
        int offset = 0;
        ushort ident = Primitives.ReadU16(span, ref offset);
        ulong ver = Primitives.ReadUvarint(span, ref offset);
        return (ident, (int)ver, descriptor.Slice(offset));
    }

    /// <summary>Materialize DIRECT-1 content (full copy).</summary>
    public static byte[] MaterializeDirect(ReadOnlyMemory<byte> remainder)
    {
        return remainder.ToArray();
    }

    /// <summary>Materialize EXTENTS-1 content (operation collection).</summary>
    public static byte[] MaterializeExtents(ReadOnlyMemory<byte> remainder, Func<ulong, byte[]> resolve)
    {
        var span = remainder.Span;
        int offset = 0;
        ulong opCount = Primitives.ReadUvarint(span, ref offset);
        var result = new List<byte>();
        for (ulong i = 0; i < opCount; i++)
        {
            var opResult = MaterializeOperation(remainder, ref offset, resolve, new HashSet<ulong>());
            result.AddRange(opResult);
        }
        if (offset != remainder.Length)
            throw new VsnException(0x000C, "trailing bytes after EXTENTS-1 operations");
        return result.ToArray();
    }

    /// <summary>Yield EXTENTS-1 content in chunks (LITERAL/COPY slices).</summary>
    public static IEnumerable<byte[]> MaterializeExtentsStream(
        ReadOnlyMemory<byte> remainder, Func<ulong, byte[]> resolve, int chunkSize = 65536)
    {
        var span = remainder.Span;
        int offset = 0;
        ulong opCount = Primitives.ReadUvarint(span, ref offset);
        for (ulong i = 0; i < opCount; i++)
        {
            var buf = MaterializeOperation(remainder, ref offset, resolve, new HashSet<ulong>());
            for (int k = 0; k < buf.Length; k += chunkSize)
                yield return buf[k..Math.Min(k + chunkSize, buf.Length)];
        }
        if (offset != remainder.Length)
            throw new VsnException(0x000C, "trailing bytes after EXTENTS-1 operations");
    }


    private static byte[] MaterializeOperation(ReadOnlyMemory<byte> data, ref int offset, Func<ulong, byte[]> resolve, HashSet<ulong> visited)
    {
        var span = data.Span;
        ulong kind = Primitives.ReadUvarint(span, ref offset);
        if (kind != Constants.OpNested)
            throw new VsnException(0x000C, $"operation must be NESTED, got kind {kind}");
        ulong n = Primitives.ReadUvarint(span, ref offset);
        var operands = new List<(string type, object value)>();
        for (ulong i = 0; i < n; i++)
        {
            operands.Add(ReadOperand(span, ref offset));
        }
        return ApplyOperation(operands, resolve, visited);
    }

    private static (string type, object value) ReadOperand(ReadOnlySpan<byte> span, ref int offset)
    {
        ulong kind = Primitives.ReadUvarint(span, ref offset);
        if (kind == Constants.OpLiteralBytes)
        {
            ulong ln = Primitives.ReadUvarint(span, ref offset);
            var val = span.Slice(offset, (int)ln).ToArray();
            offset += (int)ln;
            return ("lit", val);
        }
        if (kind == Constants.OpObjectSource)
        {
            ulong serial = Primitives.ReadUvarint(span, ref offset);
            return ("src", serial);
        }
        if (kind == Constants.OpNumeric)
        {
            ulong num = Primitives.ReadUvarint(span, ref offset);
            return ("num", num);
        }
        if (kind == Constants.OpNested)
        {
            ulong n = Primitives.ReadUvarint(span, ref offset);
            var nested = new List<(string, object)>();
            for (ulong i = 0; i < n; i++)
                nested.Add(ReadOperand(span, ref offset));
            return ("nested", nested);
        }
        throw new VsnException(0x0006, $"unknown operand kind {kind}");
    }

    private static byte[] ApplyOperation(List<(string type, object value)> operands, Func<ulong, byte[]> resolve, HashSet<ulong> visited)
    {
        if (operands.Count == 0)
            throw new VsnException(0x000C, "empty operation");
        var head = operands[0];
        if (head.type == "src")
        {
            if (operands.Count != 3 || operands[1].type != "num" || operands[2].type != "num")
                throw new VsnException(0x000C, "malformed COPY operation");
            ulong source = (ulong)head.value;
            ulong off = (ulong)operands[1].value;
            ulong length = (ulong)operands[2].value;
            if (visited.Contains(source))
                throw new VsnException(0x000C, $"dependency cycle at ObjectSerial {source}");
            var srcBytes = resolve(source);
            if (off + length > (ulong)srcBytes.Length)
                throw new VsnException(0x000C, "COPY range out of bounds");
            return srcBytes[(int)off..(int)(off + length)];
        }
        if (head.type == "lit")
        {
            return (byte[])head.value;
        }
        throw new VsnException(0x000C, $"unknown operation head kind {head.type}");
    }
}
