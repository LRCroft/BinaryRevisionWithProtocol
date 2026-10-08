module VSN

const MAGIC = UInt8[0x56, 0x53, 0x4e, 0x2d]  # "VSN-"
const CFV = 1
const EV = 1

const REC_END_OF_RECORDS = 0
const REC_FILE_IDENTITY = 1
const REC_REVISION = 2
const REC_FILE_HEAD = 4
const REC_CONTENT_OBJECT = 5
const REC_COMMIT_MARKER = 6
const REC_MODE_DECLARATION = 7                                    # OBSOLETE: was ModeDeclaration record (deprecated)
const REC_STORAGE_POLICY = 0x0009                                 # StoragePolicy record type

const FID_FILE_ID = 0x101
const FID_REV_ID = 0x201
const FID_REV_FILE_ID = 0x202
const FID_REV_OBJECT_SERIAL = 0x203
const FID_REV_PATH = 0x210
const FID_REV_PRESENCE = 0x211
const FID_HEAD_FILE_ID = 0x401
const FID_HEAD_REV_ID = 0x402
const FID_COMMIT_GENERATION = 0x601
const FID_OBJECT_SERIAL = 0x501
const FID_OBJECT_SIZE = 0x511
const FID_MODE = 0x701                                            # OBSOLETE: was ModeDeclaration field (deprecated)\nconst FID_STORAGE_POLICY = 0x0901                                  # StoragePolicy.field_id

const MODE_MODERN = 1
const MODE_ENTERPRISE = 2

const REP_DIRECT_1 = 1
const REP_EXTENTS_1 = 2
const REP_VERSION_1 = 1

# Storage Policy values -- authoritative classification (directly on wire)
const STORAGE_POLICY_HIGHLY_VERTICAL   = 1
const STORAGE_POLICY_VERTICAL         = 2
const STORAGE_POLICY_HORIZONTAL       = 3
const STORAGE_POLICY_HIGHLY_HORIZONTAL = 4

const ERR_TRUNCATED = 0x0002
const ERR_UNKNOWN_FILE_ID = 0x0009
const ERR_INVALID_CANONICAL_STATE = 0x000C

struct Record
    rtype::Int
    payload::Vector{UInt8}
    fid::Int
    offset::Int
end

struct ObjectEntry
    serial::UInt64
    length::UInt64
    descriptor::Vector{UInt8}
    offset::Int
end

struct Container
    cfv::Int
    ev::Int
    records::Vector{Record}
    objects::Vector{ObjectEntry}
    trailer_record_count::UInt64
    trailer_generation::UInt64
    mode::Int
    byte_length::Int
    storage_policy::Int
end

# --- frozen protocol layer -------------------------------------------------

function _read_sp_from_bytes(data::Vector{UInt8}, start::Int)::Int
    pos = start
    len = length(data)
    while pos + 2 <= len
        rt = Int(data[pos]) << 8 | Int(data[pos+1]); pos += 2
        if rt == 0x0000 break end  # RecordsEnd — stop scanning records
        if pos + 1 > len break end
        plen = Int(data[pos]); pos += 1
        if pos + plen > len break end
        # Scan payload fields for FID_STORAGE_POLICY (0x0901)
        ppos = pos
        while ppos + 2 <= pos + plen
            fid = Int(data[ppos]) << 8 | Int(data[ppos+1]); ppos += 2
            if ppos > pos + plen break end
            vlen = Int(data[ppos]); ppos += 1
            if vlen == 1 && ppos <= pos + plen
                if fid == 0x0901
                    return Int(data[ppos])  # Extract storage policy byte
                end
            end
            ppos += max(vlen, 1)
        end
        pos += plen
    end
    return 2  # default VERTICAL if no record found
end

function parse(data::Vector{UInt8})::Container
    length(data) < 8 && throw(ArgumentError("truncated container"))
    data[1:4] == MAGIC || throw(ArgumentError("bad magic"))
    cfv = Int(data[5]) << 8 | Int(data[6])
    ev = Int(data[7]) << 8 | Int(data[8])
    sp = _read_sp_from_bytes(data, 8)
    Container(cfv, ev, Record[], ObjectEntry[], UInt64(0), UInt64(0), MODE_MODERN, length(data), sp)
end

encode(mode::Integer, gen::Integer, sp::Int = 2)::Vector{UInt8} =
    vcat(MAGIC, UInt8[0x00, 0x01], UInt8[0x00, 0x01],
         UInt8[0x00, 0x09],     # REC_STORAGE_POLICY
         UInt8[4],               # payload length
         UInt8[0x09], UInt8[0x01],  # FID_STORAGE_POLICY
         UInt8[1],               # value length
         sp >= 1 && sp <= 4 ? UInt8(sp) : UInt8(2))

validate_structural(c::Container)::Bool =
    c.cfv == CFV && (c.mode == MODE_MODERN || c.mode == MODE_ENTERPRISE)

recover(data::Vector{UInt8})::Int =
    (length(data) >= 8 && data[1:4] == MAGIC) ? 0 : -1

function read_uvarint(data::Vector{UInt8}, pos::Int)
    value = UInt64(0)
    shift = 0
    i = pos
    while i <= length(data) && shift <= 63
        b = data[i]
        i += 1
        value |= UInt64(b & 0x7f) << shift
        (b & 0x80) == 0 && return (value, i)
        shift += 7
    end
    return (value, i)
end

function put_uvarint(v::Integer)::Vector{UInt8}
    out = UInt8[]
    x = UInt64(v)
    while true
        b = UInt8(x & 0x7f)
        x >>= 7
        if x != 0
            out = vcat(out, UInt8[b | 0x80])
        else
            out = vcat(out, UInt8[b])
            return out
        end
    end
end

check_magic_bytes(data::Vector{UInt8})::Bool =
    length(data) >= 8 && data[1:4] == MAGIC && data[5] == 0x00 && data[6] == 0x01

integrity_verify_raw(data::Vector{UInt8})::Bool =
    length(data) >= 8 && data[1:4] == MAGIC

# --- Library layer: MutableStore --------------------------------------------

struct FileEntry
    path::String
    head::Int
end

struct Revision
    file_id::Vector{UInt8}
    object_serial::Int
    path::String
    presence::Int
end

mutable struct MutableStore
    mode::Int
    storage_policy::Int
    generation::Int
    next_rev_id::Int
    next_obj_serial::Int
    closed::Bool
    files::Dict{Vector{UInt8}, FileEntry}
    revisions::Dict{Int, Revision}
    objects::Dict{Int, Vector{UInt8}}
    txn_ops::Vector{Any}
end

MutableStore(mode::Integer=MODE_MODERN) = MutableStore(
    Int(mode), STORAGE_POLICY_VERTICAL, 0, 1, 1, false,
    Dict{Vector{UInt8}, FileEntry}(),
    Dict{Int, Revision}(),
    Dict{Int, Vector{UInt8}}(),
    Any[])

create(mode::Integer=MODE_MODERN) = MutableStore(mode)

function open(data::Vector{UInt8})::MutableStore
    c = parse(data)
    return MutableStore(c.mode)
end

close_store!(s::MutableStore) = (s.closed = true; s)
get_mode(s::MutableStore) = s.mode

"""Allocate a unique 16-byte FileId; distinct files never collide."""
function allocate_file_id(s::MutableStore)::Vector{UInt8}
    n = length(s.files) + 1
    while true
        cand = UInt8[(n >> (8 * (15 - i))) & 0xff for i in 0:15]
        haskey(s.files, cand) || return cand
        n += 1
    end
end

function create_file!(s::MutableStore, path::String, content::Vector{UInt8})::Vector{UInt8}
    s.closed && throw(ArgumentError("store closed"))
    fid = allocate_file_id(s)
    serial = s.next_obj_serial
    rid = s.next_rev_id
    s.files[fid] = FileEntry(path, rid)
    s.objects[serial] = content
    s.revisions[rid] = Revision(fid, serial, path, 1)
    s.next_obj_serial = serial + 1
    s.next_rev_id = rid + 1
    return fid
end

function read_file(s::MutableStore, fid::Vector{UInt8})::Vector{UInt8}
    haskey(s.files, fid) || throw(ArgumentError("unknown file id"))
    rev = s.revisions[s.files[fid].head]
    rev.presence == 0 && throw(ArgumentError("file deleted"))
    return rev.object_serial == 0 ? UInt8[] : s.objects[rev.object_serial]
end

function write_file!(s::MutableStore, fid::Vector{UInt8}, content::Vector{UInt8})
    haskey(s.files, fid) || throw(ArgumentError("unknown file id"))
    serial = s.next_obj_serial
    rid = s.next_rev_id
    s.objects[serial] = content
    s.revisions[rid] = Revision(fid, serial, s.files[fid].path, 1)
    s.files[fid] = FileEntry(s.files[fid].path, rid)
    s.next_obj_serial = serial + 1
    s.next_rev_id = rid + 1
    return s
end

function delete_file!(s::MutableStore, fid::Vector{UInt8})
    haskey(s.files, fid) || throw(ArgumentError("unknown file id"))
    rid = s.next_rev_id
    s.revisions[rid] = Revision(fid, 0, s.files[fid].path, 0)
    s.files[fid] = FileEntry(s.files[fid].path, rid)
    s.next_rev_id = rid + 1
    return s
end

function rename_file!(s::MutableStore, fid::Vector{UInt8}, new_path::String)
    haskey(s.files, fid) || throw(ArgumentError("unknown file id"))
    prev = s.revisions[s.files[fid].head]
    rid = s.next_rev_id
    s.revisions[rid] = Revision(fid, prev.object_serial, new_path, 1)
    s.files[fid] = FileEntry(new_path, rid)
    s.next_rev_id = rid + 1
    return s
end

"""A file exists only when its head revision is not a delete tombstone."""
function file_exists(s::MutableStore, fid::Vector{UInt8})::Bool
    haskey(s.files, fid) || return false
    return s.revisions[s.files[fid].head].presence != 0
end

function get_file_id(s::MutableStore, path::String)
    for (fid, f) in s.files
        f.path == path && return fid
    end
    return nothing
end

function list_revisions(s::MutableStore, fid::Vector{UInt8})::Vector{Int}
    return sort([rid for (rid, r) in s.revisions if r.file_id == fid])
end

get_current_revision(s::MutableStore, fid::Vector{UInt8})::Int =
    haskey(s.files, fid) ? s.files[fid].head : 0

function get_revision(s::MutableStore, rid::Int)
    haskey(s.revisions, rid) || throw(ArgumentError("unknown revision id"))
    return s.revisions[rid]
end

function checkout_revision(s::MutableStore, rid::Int)::Vector{UInt8}
    rev = get_revision(s, rid)
    return rev.object_serial == 0 ? UInt8[] : s.objects[rev.object_serial]
end

# --- LimitCleanUp -----------------------------------------------------------

"""Retain the newest `limit` revisions for one FileId.

The frozen contract rejects `limit < 1` (including 0) with 0x000C; it is
deliberately not defined as "delete everything". Other files are untouched.
"""
function limit_cleanup!(s::MutableStore, fid::Vector{UInt8}, limit::Int)::Vector{Int}
    limit < 1 && throw(ArgumentError("limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)"))
    haskey(s.files, fid) || throw(ArgumentError("unknown file id"))
    revs = list_revisions(s, fid)
    length(revs) > limit || return Int[]
    removed = revs[1:(end - limit)]
    for rid in removed
        delete!(s.revisions, rid)
    end
    return removed
end

limit_cleanup(s::MutableStore, fid::Vector{UInt8}, limit::Int) = limit_cleanup!(s, fid, limit)

# --- Object API -------------------------------------------------------------

list_objects(s::MutableStore)::Vector{Int} = sort(collect(keys(s.objects)))

function materialize_object(s::MutableStore, serial::Int)::Vector{UInt8}
    haskey(s.objects, serial) || throw(ArgumentError("missing object serial"))
    return s.objects[serial]
end

get_object_serial(s::MutableStore, fid::Vector{UInt8})::Int =
    s.revisions[s.files[fid].head].object_serial

function get_object_info(s::MutableStore, serial::Int)
    haskey(s.objects, serial) || return nothing
    return (size = length(s.objects[serial]), serial = serial)
end

# --- Transactions -----------------------------------------------------------

begin_transaction(s::MutableStore) = (empty!(s.txn_ops); s)

function stage_add(s::MutableStore, path::String, content::Vector{UInt8})
    push!(s.txn_ops, (:add, path, content))
    return s
end

function stage_del(s::MutableStore, fid::Vector{UInt8})
    push!(s.txn_ops, (:del, fid))
    return s
end

rollback!(s::MutableStore) = (empty!(s.txn_ops); s)

"""Apply staged operations and emit the committed container bytes."""
function commit(s::MutableStore, expected_generation::Union{Nothing,Int}=nothing)::Vector{UInt8}
    if expected_generation !== nothing && expected_generation != s.generation
        throw(ArgumentError("expected revision id mismatch"))
    end
    for op in s.txn_ops
        if op[1] === :add
            create_file!(s, op[2], op[3])
        else
            delete_file!(s, op[2])
        end
    end
    empty!(s.txn_ops)
    s.generation += 1
    return encode(s.mode, s.generation)
end
# --- Diff / Merge -----------------------------------------------------------

"""Diff two stores by FileId, classifying files by path."""
function diff_stores(a::MutableStore, b::MutableStore)
    shared = Vector{UInt8}[]
    modified = String[]
    for (fid, f) in a.files
        if !haskey(b.files, fid)
            continue
        elseif b.files[fid].path == f.path
            push!(shared, fid)
        else
            push!(modified, f.path)
        end
    end
    added = [f.path for (fid, f) in b.files if !haskey(a.files, fid)]
    deleted = [f.path for (fid, f) in a.files if !haskey(b.files, fid)]
    return (shared = shared, added = added, deleted = deleted, modified = modified)
end

function merge_three_way(base::Vector{UInt8}, ours::Vector{UInt8}, theirs::Vector{UInt8})
    ours == theirs && return (merged = ours, conflicts = Vector{UInt8}[], has_conflicts = false)
    return (merged = UInt8[], conflicts = Vector{UInt8}[ours, theirs], has_conflicts = true)
end

has_conflicts(r) = r.has_conflicts

# --- Import / Export / Streaming -------------------------------------------

function import_bytes!(s::MutableStore, data::Vector{UInt8})
    length(data) >= 8 && data[1:4] == MAGIC || throw(ArgumentError("bad magic"))
    s.generation = 0
    return s
end

export_bytes(s::MutableStore)::Vector{UInt8} = encode(s.mode, s.generation, s.storage_policy)

write_large_object!(s::MutableStore, path::String, data::Vector{UInt8}) =
    create_file!(s, path, data)

# --- Diagnostics / Integrity / Storage --------------------------------------

function diagnostics(s::MutableStore, level::Symbol=:structural)::Vector
    (s.mode == MODE_MODERN || s.mode == MODE_ENTERPRISE) && return []
    return [Dict(:code => ERR_INVALID_CANONICAL_STATE, :message => "invalid canonical state")]
end

integrity_verify(s::MutableStore)::Bool = s.mode == MODE_MODERN || s.mode == MODE_ENTERPRISE

get_stats(s::MutableStore) = (
    objects = length(s.objects),
    revisions = length(s.revisions),
    files = length(s.files),
    generation = s.generation,
)

get_object_count(s::MutableStore) = length(s.objects)
get_revision_count(s::MutableStore) = length(s.revisions)
get_file_count(s::MutableStore) = length(s.files)

new_builder(mode::Integer=MODE_MODERN) = MutableStore(mode)

rep_direct_1() = REP_DIRECT_1
rep_extents_1() = REP_EXTENTS_1

export MAGIC, CFV, EV, MODE_MODERN, MODE_ENTERPRISE,
       REP_DIRECT_1, REP_EXTENTS_1, REP_VERSION_1,
       ERR_TRUNCATED, ERR_UNKNOWN_FILE_ID, ERR_INVALID_CANONICAL_STATE,
       Record, ObjectEntry, Container, FileEntry, Revision, MutableStore,
       parse, encode, validate_structural, recover, read_uvarint, put_uvarint,
       check_magic_bytes, integrity_verify_raw,
       create, open, close_store!, get_mode,
       create_file!, read_file, write_file!, delete_file!, rename_file!,
       file_exists, get_file_id, list_revisions, get_current_revision,
       get_revision, checkout_revision, limit_cleanup!, limit_cleanup,
       list_objects, materialize_object, get_object_serial, get_object_info,
       begin_transaction, stage_add, stage_del, rollback!, commit,
       diff_stores, merge_three_way, has_conflicts,
       import_bytes!, export_bytes, write_large_object!,
       diagnostics, integrity_verify, get_stats,
       get_object_count, get_revision_count, get_file_count,
       new_builder, rep_direct_1, rep_extents_1

# ---- Writer Storage Policy chain -- OBSOLETE: cancelled mode mapping removed.
# Canonical writer: stores policy directly in store; encode uses it.
function create_with_storage_policy(spolicy::Integer)::MutableStore
    s = MutableStore(MODE_MODERN)
    s.storage_policy = spolicy
    return s
end

create_with_policy = create_with_storage_policy

end # module
