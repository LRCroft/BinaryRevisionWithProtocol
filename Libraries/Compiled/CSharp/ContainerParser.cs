namespace Vsn;

/// <summary>
/// VSN container parser: streaming, framing-exact, mode-independent.
/// Parsing never requires a hash, index, cache, checkpoint, or external data.
/// Unknown records and fields are skipped by declared length (GR-29..GR-33).
/// </summary>
public static class ContainerParser
{
    private static ReadOnlyMemory<byte> SliceChecked(ReadOnlyMemory<byte> data, int offset, int length, string what)
    {
        if (length < 0 || offset < 0 || offset + length > data.Length)
            throw new VsnException(0x0002, $"truncated {what}", offset);
        return data.Slice(offset, length);
    }

    public static ParsedContainer Parse(ReadOnlyMemory<byte> data)
    {
        var span = data.Span;
        int offset = 0;

        // Magic
        if (span.Length < 4 || !span[..4].SequenceEqual(Constants.Magic))
            throw new VsnException(0x0001, "bad magic", 0);
        offset = 4;

        // ContainerFormatVersion
        ushort cfv = Primitives.ReadU16(span, ref offset);
        if (cfv != 1)
            throw new VsnException(0x0003, $"unsupported container format version {cfv}");

        // EncodingVersion
        ushort ev = Primitives.ReadU16(span, ref offset);
        if (ev != 1)
            throw new VsnException(0x0004, $"unsupported encoding version {ev}");

        // Header fields until RecordsEnd
        while (true)
        {
            ushort fid = Primitives.ReadU16(span, ref offset);
            ulong ln = Primitives.ReadUvarint(span, ref offset);
            if (fid == Constants.FidRecordsEnd)
            {
                if (ln != 0)
                    throw new VsnException(0x0001, "RecordsEnd length must be 0");
                break;
            }
            offset += checked((int)ln); // skip unknown header fields
            if (offset > data.Length)
                throw new VsnException(0x0002, "truncated header field", offset);
        }

        var container = new ParsedContainer(cfv, ev, 0, 0, data.Length);

        // Records
        while (true)
        {
            int start = offset;
            ushort rt = Primitives.ReadU16(span, ref offset);
            if (rt == Constants.RecEndOfRecords)
                break; // bare 2-byte end-of-records marker (GR-10/11)
            ulong rl = Primitives.ReadUvarint(span, ref offset);
            var payload = SliceChecked(data, offset, checked((int)rl), "record payload");
            offset += (int)rl;
            var rec = new Record(rt, payload, start);
            if (rt <= Constants.RecRepresentationDescriptor || rt == Constants.RecStoragePolicy)
                ParseFields(payload.Span, rec);
            container.Records.Add(rec);
        }

        // Objects
        while (true)
        {
            int start = offset;
            ulong serial = Primitives.ReadUvarint(span, ref offset);
            if (serial == 0)
                break; // end-of-objects marker (GR-37)
            ulong ol = Primitives.ReadUvarint(span, ref offset);
            var desc = SliceChecked(data, offset, checked((int)ol), "object descriptor");
            offset += (int)ol;
            container.Objects.Add(new ObjectEntry(new ObjectSerial(serial), (int)ol, desc, start));
        }

        // Trailer
        ulong rc = Primitives.ReadUvarint(span, ref offset);
        ulong gen = Primitives.ReadUvarint(span, ref offset);

        // Update trailer values (create new container with same records/objects)
        var finalContainer = new ParsedContainer(cfv, ev, rc, gen, data.Length);
        finalContainer.Records.AddRange(container.Records);
        finalContainer.Objects.AddRange(container.Objects);
        container = finalContainer;

        // Extract mode and storage_policy
        bool hasModeDecl = false;
        foreach (var rec in container.Records)
        {
            if (rec.RType == Constants.RecModeDeclaration)
            {
                var m = rec.GetField(Constants.FidMode);
                if (m != null && m.Value.Length > 0)
                    container.Mode = m.Value.Span[0];
                    hasModeDecl = true;
            }
            if (rec.RType == Constants.RecStoragePolicy)
            {
                var sp = rec.GetField(Constants.FidStoragePolicy);
                if (sp != null && sp.Value.Length > 0)
                    container.StoragePolicy = sp.Value.Span[0];
            }
        }
        // Derive mode from storage_policy when no ModeDeclaration present (canonical writers)
        if (!hasModeDecl && container.StoragePolicy.HasValue)
        {
            var spVal = container.StoragePolicy.Value;
            if (spVal >= 1 && spVal <= 4)
            {
                container.Mode = (spVal >= 3) ? Constants.ModeEnterprise : Constants.ModeModern;
            }
        }

        return container;
    }

    private static void ParseFields(ReadOnlySpan<byte> payload, Record rec)
    {
        int offset = 0;
        ushort last = 0;
        bool first = true;
        while (offset < payload.Length)
        {
            int start = offset;
            ushort fid = Primitives.ReadU16(payload, ref offset);
            if (!first && fid <= last)
                throw new VsnException(0x0011, $"FieldId {fid} not strictly ascending", start);
            last = fid;
            first = false;
            ulong ln = Primitives.ReadUvarint(payload, ref offset);
            var val = SliceChecked(rec.Payload, offset, checked((int)ln), "field value");
            offset += (int)ln;
            rec.Fields.Add(new Field(fid, val));
        }
    }
}

