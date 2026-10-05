namespace Vsn;

/// <summary>
/// VSN-1 frozen record, field, and registry constants (GR-28, GR-17, VR-*).
/// Values are protocol-assigned and MUST NOT be invented by a library.
/// </summary>
public static class Constants
{
    // Record types (GR-28)
    public const ushort RecEndOfRecords = 0x0000;
    public const ushort RecFileIdentity = 0x0001;
    public const ushort RecRevision = 0x0002;
    public const ushort RecRevisionSet = 0x0003;
    public const ushort RecFileHead = 0x0004;
    public const ushort RecContentObject = 0x0005;
    public const ushort RecCommitMarker = 0x0006;
    public const ushort RecModeDeclaration = 0x0007;
    public const ushort RecRepresentationDescriptor = 0x0008;
    public const ushort RecExtensionMin = 0x8000;
    public const ushort RecExtensionMax = 0xFFFE;
    public const ushort RecReserved = 0xFFFF;

    // Field IDs (GR-17)
    public const ushort FidRecordsEnd = 0x0000;
    public const ushort FidFileId = 0x0101;          // FileIdentity.FileId (normative)
    public const ushort FidRevId = 0x0201;
    public const ushort FidRevFileId = 0x0202;
    public const ushort FidRevObjectSerial = 0x0203;
    public const ushort FidRevPath = 0x0210;
    public const ushort FidRevPresence = 0x0211;
    public const ushort FidRsetId = 0x0301;
    public const ushort FidRsetMembers = 0x0302;
    public const ushort FidRsetState = 0x0303;
    public const ushort FidRsetDigest = 0x0310;
    public const ushort FidHeadFileId = 0x0401;
    public const ushort FidHeadRevId = 0x0402;
    public const ushort FidHeadGeneration = 0x0410;
    public const ushort FidObjectSerial = 0x0501;
    public const ushort FidObjectHash = 0x0510;
    public const ushort FidObjectSize = 0x0511;
    public const ushort FidCommitGeneration = 0x0601;
    public const ushort FidCommitHash = 0x0610;
    public const ushort FidMode = 0x0701;
    public const ushort FidRepIdentity = 0x0801;
    public const ushort FidRepVersion = 0x0802;
    public const ushort FidRepMetadata = 0x0810;

    // VSN modes (GR-38)
    public const byte ModeModern = 0x01;
    public const byte ModeEnterprise = 0x02;

    // Representation identities (VR-*)
    public const ushort RepDirect1 = 0x0001;
    public const ushort RepExtents1 = 0x0002;
    public const int RepVersion1 = 1;

    // Presence (SR-09)
    public const byte Present = 1;
    public const byte Deleted = 2;
    public const byte Directory = 3;

    // Operand kind tags (VR-23)
    public const int OpLiteralBytes = 0;
    public const int OpObjectSource = 1;
    public const int OpNumeric = 2;
    public const int OpNested = 3;

    // Magic bytes
    public static readonly byte[] Magic = "VSN-"u8.ToArray();
}
