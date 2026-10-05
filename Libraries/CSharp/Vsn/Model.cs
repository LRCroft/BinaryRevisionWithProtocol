namespace Vsn;

/// <summary>16-byte logical file identity (UUID).</summary>
public readonly record struct FileId(ReadOnlyMemory<byte> Value)
{
    public FileId(byte[] value) : this(value.AsMemory()) { }
}

/// <summary>Immutable revision identity (uvarint).</summary>
public readonly record struct RevisionId(ulong Value);

/// <summary>Container-scoped canonical content-object identity (uvarint).</summary>
public readonly record struct ObjectSerial(ulong Value);

/// <summary>A parsed field within a record.</summary>
public sealed class Field
{
    public ushort Fid { get; }
    public ReadOnlyMemory<byte> Value { get; }

    public Field(ushort fid, ReadOnlyMemory<byte> value)
    {
        Fid = fid;
        Value = value;
    }

    public ulong AsUvarint()
    {
        int offset = 0;
        return Primitives.ReadUvarint(Value.Span, ref offset);
    }
}

/// <summary>A parsed record.</summary>
public sealed class Record
{
    public ushort RType { get; }
    public ReadOnlyMemory<byte> Payload { get; }
    public List<Field> Fields { get; } = new();
    public int ByteOffset { get; }

    public Record(ushort rtype, ReadOnlyMemory<byte> payload, int byteOffset = 0)
    {
        RType = rtype;
        Payload = payload;
        ByteOffset = byteOffset;
    }

    public Field? GetField(ushort fid)
    {
        foreach (var f in Fields)
            if (f.Fid == fid) return f;
        return null;
    }
}

/// <summary>A parsed object entry in the object section.</summary>
public sealed class ObjectEntry
{
    public ObjectSerial Serial { get; }
    public int Length { get; }
    public ReadOnlyMemory<byte> Descriptor { get; }
    public int ByteOffset { get; }

    public ObjectEntry(ObjectSerial serial, int length, ReadOnlyMemory<byte> descriptor, int byteOffset = 0)
    {
        Serial = serial;
        Length = length;
        Descriptor = descriptor;
        ByteOffset = byteOffset;
    }
}

/// <summary>A parsed VSN-1 container.</summary>
public sealed class ParsedContainer
{
    public int ContainerFormatVersion { get; }
    public int EncodingVersion { get; }
    public List<Record> Records { get; } = new();
    public List<ObjectEntry> Objects { get; } = new();
    public ulong TrailerRecordCount { get; }
    public ulong TrailerGeneration { get; }
    public byte? Mode { get; set; }
    public int ByteLength { get; }

    public ParsedContainer(int cfv, int ev, ulong trailerRc, ulong trailerGen, int byteLength)
    {
        ContainerFormatVersion = cfv;
        EncodingVersion = ev;
        TrailerRecordCount = trailerRc;
        TrailerGeneration = trailerGen;
        ByteLength = byteLength;
    }
}
