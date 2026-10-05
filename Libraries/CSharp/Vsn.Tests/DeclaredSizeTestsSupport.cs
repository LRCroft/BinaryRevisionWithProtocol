using Vsn;
using Xunit;

namespace Vsn.Tests;

/// <summary>Helpers for the 0x0511 declared-size regression tests.</summary>
public static class DeclaredSizeTestsSupport
{
    /// <summary>
    /// Re-encode a container forcing a specific ObjectSerial's declared 0x0511.
    /// Used to prove DR-6 rejects a declared size that disagrees with the
    /// materialized length (frozen vector EXT-12).
    /// </summary>
    public static byte[] WithDeclaredSize(byte[] data, ulong serial, ulong size)
    {
        var parsed = ContainerParser.Parse(data);
        var records = new List<(ushort, List<(ushort, byte[])>)>();
        var objects = new List<(ulong, byte[])>();
        foreach (var rec in parsed.Records)
        {
            var fields = rec.Fields
                .Where(f => f.Fid != Constants.FidObjectSize)
                .Select(f => (f.Fid, f.Value.ToArray()))
                .ToList();
            if (rec.RType == Constants.RecContentObject)
            {
                var s = rec.GetField(Constants.FidObjectSerial);
                if (s != null && s.AsUvarint() == serial)
                    fields.Add((Constants.FidObjectSize, Primitives.PutUvarint(size)));
            }
            records.Add((rec.RType, fields));
        }
        foreach (var obj in parsed.Objects)
            objects.Add((obj.Serial.Value, obj.Descriptor.ToArray()));
        return Writer.Encode(parsed.Mode ?? Constants.ModeModern, records, objects,
                             parsed.TrailerGeneration);
    }
}