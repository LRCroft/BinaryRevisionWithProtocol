#!/usr/bin/env python3
"""Generate new VSN-1 containers with REC_STORAGE_POLICY (0x0009) for all four policies."""
import struct, os, hashlib, uuid

BASE = r'C:\CampMember\BinaryRevisionWithProtocol\Libraries\Conformance\corpus\scenarios'

def put_u16(v): return v.to_bytes(2, 'big')
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

def make_policy_container(policy_value, file_name='doc.txt', content=b'data-for-policy-test'):
    """Build a VSN-1 container with REC_STORAGE_POLICY (0x0009) and one file.
    
    StoragePolicy record format per spec:
      Record type (0x0009) [2B] + payload length varint [1B] + 
      field (FID 0x0901 [2B] + val_len=1 [1B] + value u8 [1B]) = 7 bytes total
    """
    file_id = uuid.uuid4().bytes  # 16 bytes
    
    out = bytearray(b'VSN-')
    out += put_u16(1)        # ContainerFormatVersion
    out += put_u16(1)        # EncodingVersion
    out += _field(0x0000, b'')  # RecordsEnd header marker
    
    # StoragePolicy record (NEW: replaces ModeDeclaration)
    out += _record(0x0009, [(0x0901, bytes([policy_value]))])
    
    # FileIdentity record
    out += _record(0x0001, [(0x0101, file_id)])
    
    # Revision record
    rev_id = 1
    rev_fields = [
        (0x0201, put_uvarint(rev_id)),
        (0x0202, file_id),
        (0x0203, put_uvarint(1)),  # object serial
        (0x0210, file_name.encode('utf-8')),
        (0x0211, b'\x01'),  # presence = PRESENT
    ]
    out += _record(0x0002, rev_fields)
    
    # FileHead record
    out += _record(0x0004, [
        (0x0401, file_id),
        (0x0402, put_uvarint(rev_id)),
    ])
    
    # ContentObject record
    sha = hashlib.sha256(content).digest()
    obj_fields = [
        (0x0501, put_uvarint(1)),  # object serial
        (0x0510, bytes([0x01]) + sha),  # hash algorithm SHA-256 + digest
        (0x0511, put_uvarint(len(content))),  # declared content length
    ]
    out += _record(0x0005, obj_fields)
    
    # CommitMarker record
    commit_hash = hashlib.sha256(b'commit-gen-1').digest()
    cm_fields = [
        (0x0601, put_uvarint(1)),  # generation
        (0x0610, commit_hash),     # commit hash
    ]
    out += _record(0x0006, cm_fields)
    
    # End-of-records marker
    out += put_u16(0x0000)
    
    # Objects section
    # Object serial + descriptor length + descriptor
    descriptor = put_u16(0x0001) + put_uvarint(0x0001) + content  # DIRECT-1 v1 + raw content
    out += put_uvarint(1)          # object serial
    out += put_uvarint(len(descriptor))
    out += descriptor
    out += put_uvarint(0)          # end-of-objects marker
    
    # Trailer: canonical record count (excludes ModeDeclaration - we use StoragePolicy now, which counts)
    # Records: SP(1) + FileIdentity(1) + Revision(1) + FileHead(1) + ContentObject(1) + CommitMarker(1) = 6
    out += put_uvarint(6)          # canonical record count
    out += put_uvarint(1)          # generation
    
    return bytes(out)

def save(name, data):
    path = os.path.join(BASE, name)
    with open(path, 'wb') as f:
        f.write(data)
    sha = hashlib.sha256(data).hexdigest()
    print(f"  {name}: {len(data)} bytes SHA-256={sha}")

print("Generating canonical Storage Policy fixtures (NEW FORMAT)...")

# HIGHLY_VERTICAL = 1
save('policy-highly_vertical.vsn', make_policy_container(1, 'doc.txt', b'data-for-p05-logical-test'))

# VERTICAL = 2
save('policy-vertical.vsn', make_policy_container(2, 'doc.txt', b'data-for-p05-logical-test'))

# HORIZONTAL = 3
save('policy-horizontal.vsn', make_policy_container(3, 'doc.txt', b'data-for-policy-test'))

# HIGHLY_HORIZONTAL = 4
save('policy-highly_horizontal.vsn', make_policy_container(4, 'doc.txt', b'data-for-policy-test'))

print("Done. New canonical fixtures generated with REC_STORAGE_POLICY.")
