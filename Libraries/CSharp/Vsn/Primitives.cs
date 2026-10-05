namespace Vsn;

/// <summary>
/// VSN-1 primitive encoding/decoding: uvarint (LEB128), u16be, u32be, u64be.
/// </summary>
public static class Primitives
{
    /// <summary>Read a uvarint (minimal LEB128) from a ReadOnlySpan, advancing the offset.</summary>
    public static ulong ReadUvarint(ReadOnlySpan<byte> data, ref int offset)
    {
        ulong result = 0;
        int shift = 0;
        for (int i = 0; i < 10; i++)
        {
            if (offset >= data.Length)
                throw new VsnException(0x0002, "truncated uvarint");
            byte b = data[offset++];
            result |= (ulong)(b & 0x7F) << shift;
            if ((b & 0x80) == 0)
            {
                // Check minimal encoding (GR-24)
                if (i > 0 && b == 0)
                    throw new VsnException(0x0001, "non-minimal uvarint");
                return result;
            }
            shift += 7;
        }
        throw new VsnException(0x0001, "uvarint overflow");
    }

    /// <summary>Read a u16be from a ReadOnlySpan, advancing the offset.</summary>
    public static ushort ReadU16(ReadOnlySpan<byte> data, ref int offset)
    {
        if (offset + 2 > data.Length)
            throw new VsnException(0x0002, "truncated u16");
        ushort val = (ushort)((data[offset] << 8) | data[offset + 1]);
        offset += 2;
        return val;
    }

    /// <summary>Encode a uvarint (minimal LEB128).</summary>
    public static byte[] PutUvarint(ulong value)
    {
        var result = new List<byte>();
        do
        {
            byte b = (byte)(value & 0x7F);
            value >>= 7;
            if (value != 0) b |= 0x80;
            result.Add(b);
        } while (value != 0);
        return result.ToArray();
    }

    /// <summary>Encode a u16be.</summary>
    public static byte[] PutU16(ushort value)
    {
        return [(byte)(value >> 8), (byte)(value & 0xFF)];
    }
}
