namespace Vsn;

public sealed class FileRecord
{
    public byte[] FileId { get; }
    public string? Path { get; set; }
    public ulong? HeadRevision { get; set; }

    public FileRecord(byte[] fileId, string? path, ulong? headRevision)
    {
        FileId = fileId;
        Path = path;
        HeadRevision = headRevision;
    }
}

public sealed class RevisionRecord
{
    public ulong RevisionId { get; }
    public byte[] FileId { get; }
    public ulong? ObjectSerial { get; }
    public string? Path { get; }
    public byte Presence { get; }

    public RevisionRecord(ulong revisionId, byte[] fileId, ulong? objectSerial, string? path, byte presence)
    {
        RevisionId = revisionId;
        FileId = fileId;
        ObjectSerial = objectSerial;
        Path = path;
        Presence = presence;
    }
}

public sealed class ObjectInfo
{
    public ulong Serial { get; }
    public int Length { get; }
    public ushort RepresentationIdentity { get; }
    public int RepresentationVersion { get; }

    public ObjectInfo(ulong serial, int length, ushort repIdentity, int repVersion)
    {
        Serial = serial;
        Length = length;
        RepresentationIdentity = repIdentity;
        RepresentationVersion = repVersion;
    }
}

public sealed class ContainerInfo
{
    public byte Mode { get; }
    public ulong Generation { get; }
    public int FileCount { get; }
    public int ObjectCount { get; }
    public int RevisionCount { get; }

    public ContainerInfo(byte mode, ulong generation, int fileCount, int objectCount, int revisionCount)
    {
        Mode = mode;
        Generation = generation;
        FileCount = fileCount;
        ObjectCount = objectCount;
        RevisionCount = revisionCount;
    }
}
