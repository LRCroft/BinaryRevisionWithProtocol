#!/usr/bin/env python3
"""Generate negative Storage Policy corpus fixtures for Phase 2."""
import struct, os, hashlib

BASE = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Conformance\corpus\scenarios'

def put_u16(v): return v.to_bytes(2, 'big')
def put_u32(v): return v.to_bytes(4, 'big')
def put_uvarint(v):
    out = bytearray()
    while v >= 0x80:
        out.append((v & 0x7F) | 0x80)
        v >>= 7
    out.append(v)
    return bytes(out)

def _field(fid, value):
    return put_u16(fid) + put_uvarint(len(value)) + value

def _record(rtype, fields):
    payload = b''.join(_field(f, v) for f, v in fields)
    return put_u16(rtype) + put_uvarint(len(payload)) + payload

def make_container(records_and_fields, objects=(), trailer_rc=0, trailer_gen=0):
    """Build a minimal VSN container from record type+fields pairs."""
    out = bytearray(b'VSN-')
    out += put_u16(1)  # CFV
    out += put_u16(1)  # EV
    out += _field(0x0000, b'')  # RecordsEnd header marker
    for rtype, flds in records_and_fields:
        out += _record(rtype, flds)
    out += put_u16(0x0000)  # end-of-records marker
    for serial, descriptor in objects:
        out += put_uvarint(serial)
        out += put_uvarint(len(descriptor))
        out += descriptor
    out += put_uvarint(0)  # end-of-objects
    out += put_uvarint(trailer_rc)
    out += put_uvarint(trailer_gen)
    return bytes(out)

def save(name, data):
    path = os.path.join(BASE, name)
    with open(path, 'wb') as f:
        f.write(data)
    sha = hashlib.sha256(data).hexdigest()
    print(f"  {name}: {len(data)} bytes SHA-256={sha}")

print("Generating negative Storage Policy fixtures...")

# NEG-SP-001: Storage Policy value = 0
save('neg_storage_policy_0.vsn', make_container([
    (0x0009, [(0x0901, b'\x00')]),  # value=0
], trailer_rc=1))

# NEG-SP-002: Storage Policy value = 5
save('neg_storage_policy_5.vsn', make_container([
    (0x0009, [(0x0901, b'\x05')]),  # value=5
], trailer_rc=1))

# NEG-SP-003: Wrong field ID (0x0902 instead of 0x0901)
save('neg_malformed_fid.vsn', make_container([
    (0x0009, [(0x0902, b'\x01')]),  # FID is wrong
], trailer_rc=1))

# NEG-SP-004: Truncated field -- length says 2 bytes but only 1 present
# We'll build this manually for precise control
def make_truncated_field():
    out = bytearray(b'VSN-')
    out += put_u16(1) + put_u16(1)
    out += _field(0x0000, b'')  # RecordsEnd marker
    # StoragePolicy record with truncated field
    rec_type = put_u16(0x0009)
    payload_len = put_uvarint(3)  # claims 3 bytes payload
    fid = put_u16(0x0901)
    val_len = put_uvarint(2)  # claims value is 2 bytes...
    val = b'\x01'  # but only provides 1 byte!
    eor = put_u16(0x0000)  # end-of-records
    out += rec_type + payload_len + fid + val_len + val
    out += eor
    out += put_uvarint(0)  # end-of-objects
    out += put_uvarint(1) + put_uvarint(1)
    return bytes(out)
save('neg_truncated_field.vsn', make_truncated_field())

# NEG-SP-005: Truncated record -- length says 5 payload bytes but only 3 present
def make_truncated_record():
    out = bytearray(b'VSN-')
    out += put_u16(1) + put_u16(1)
    out += _field(0x0000, b'')
    # StoragePolicy record: claims length=5 but only provides 3 bytes
    rec_type = put_u16(0x0009)
    payload_len = put_uvarint(5)  # claims 5 bytes
    partial_payload = _field(0x0901, b'\x01')  # only 3 bytes: fid(2)+len(1)+val(1)... no wait
    # Actually: _field(0x0901, b'\x01') = put_u16(0x0901) + put_uvarint(1) + b'\x01' = 4 bytes
    # Let me be precise: we want length field to say N but only N-2 bytes follow
    rec_type_2 = put_u16(0x0009)
    claimed_len = put_uvarint(5)
    partial = put_u16(0x0901) + b'\x01'  # fid(2) + val_len_byte only (claims 1, but value truncated to 0 bytes)
    eor = put_u16(0x0000)
    out += rec_type_2 + claimed_len + partial
    out += eor
    out += put_uvarint(0)
    out += put_uvarint(1) + put_uvarint(1)
    return bytes(out)
save('neg_truncated_record.vsn', make_truncated_record())

# NEG-SP-006: Duplicate StoragePolicy records
save('neg_duplicate_sp.vsn', make_container([
    (0x0009, [(0x0901, b'\x01')]),  # first SP record
    (0x0009, [(0x0901, b'\x02')]),  # second SP record (duplicate!)
], trailer_rc=2))

# NEG-SP-007: Missing StoragePolicy - no SP record at all (minimal container with only EOF)
save('neg_missing_sp.vsn', make_container([], trailer_rc=0))

# NEG-SP-008: Only obsolete ModeDeclaration (no StoragePolicy)
save('neg_obsolete_mode_decl.vsn', make_container([
    (0x0007, [(0x0701, b'\x01')]),  # mode=1 (MODERN)
], trailer_rc=1))

# NEG-SP-009: Non-minimal uvarint for record length
def make_nonminimal_length():
    out = bytearray(b'VSN-')
    out += put_u16(1) + put_u16(1)
    out += _field(0x0000, b'')
    # Use non-minimal encoding: value 3 normally is just \x03, but we'll use \x83\x00 (2 bytes for value 3)
    rec_type = put_u16(0x0009)
    nonminimal_len = bytes([0x83, 0x00])  # non-minimal uvarint for value 3
    payload = _field(0x0901, b'\x01')  # proper field: fid=0x0901, len=1, val=1
    eor = put_u16(0x0000)
    out += rec_type + nonminimal_len + payload
    out += eor
    out += put_uvarint(0)
    out += put_uvarint(1) + put_uvarint(1)
    return bytes(out)
save('neg_malformed_length.vsn', make_nonminimal_length())

print("Done. All negative fixtures generated.")

