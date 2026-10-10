-- VSN Library for Lua 5.4
--
-- Faithful port of the frozen VSN protocol plus the full documented
-- Library capability surface (19 capabilities). Error identifiers are the
-- frozen registry; no new protocol codes are invented.
local vsn = {}
vsn._VERSION = "1.0.0"

-- ---------------------------------------------------------------------------
-- Frozen error registry (VR-28/VR-29)
-- ---------------------------------------------------------------------------
vsn.ERRORS = {
  [0x0000] = "OK",
  [0x0001] = "MALFORMED_CONTAINER",
  [0x0002] = "TRUNCATED",
  [0x0003] = "UNSUPPORTED_CONTAINER_VERSION",
  [0x0004] = "UNSUPPORTED_ENCODING_VERSION",
  [0x0005] = "UNSUPPORTED_PROTOCOL_VERSION",
  [0x0006] = "UNSUPPORTED_REPRESENTATION",
  [0x0007] = "UNSUPPORTED_TRANSFORM",
  [0x0008] = "MISSING_OBJECT",
  [0x0009] = "MISSING_CANONICAL_REFERENCE",
  [0x000A] = "DUPLICATE_IDENTITY",
  [0x000B] = "INVALID_RELATIONSHIP",
  [0x000C] = "INVALID_CANONICAL_STATE",
  [0x000D] = "VERIFICATION_UNAVAILABLE",
  [0x000E] = "VERIFICATION_MISMATCH",
  [0x000F] = "INVALID_UTF8",
  [0x0010] = "RESERVED_VALUE",
  [0x0011] = "INVALID_FIELD_ORDERING",
  [0x0012] = "INVALID_LENGTH",
  [0x0013] = "UNKNOWN_MANDATORY_RECORD",
  [0x0014] = "ACCESS_OR_DECRYPTION_FAILURE",
}

local function mkerr(code, message)
  local e = { code = code, message = message, name = vsn.ERRORS[code] or "UNKNOWN" }
  setmetatable(e, { __tostring = function(x) return "VsnError(" .. x.name .. ": " .. x.message .. ")" end })
  return e
end

-- Raise a frozen-code error. Errors carry the protocol identifier.
function vsn.fail(code, message)
  error(mkerr(code, message), 0)
end

-- vsn.try(fn) -> ok, value | err
function vsn.try(fn)
  local ok, r = pcall(fn)
  if ok then return true, r end
  if type(r) == "table" and r.code then return false, r end
  return false, mkerr(0x0001, tostring(r))
end

-- code_of(fn) -> "XXXX" hex code, or nil when fn unexpectedly succeeded
function vsn.code_of(fn)
  local ok, r = pcall(fn)
  if ok then return nil end
  if type(r) == "table" and r.code then return string.format("%04X", r.code) end
  return "UNEXPECTED:" .. tostring(r)
end

-- ---------------------------------------------------------------------------
-- Frozen protocol constants (GR-28, GR-17, VR-*)
-- ---------------------------------------------------------------------------
vsn.REC_END_OF_RECORDS = 0x0000
vsn.REC_FILE_IDENTITY = 0x0001
vsn.REC_REVISION = 0x0002
vsn.REC_REVISION_SET = 0x0003
vsn.REC_FILE_HEAD = 0x0004
vsn.REC_CONTENT_OBJECT = 0x0005
vsn.REC_COMMIT_MARKER = 0x0006
vsn.REC_MODE_DECLARATION = 0x0007  -- OBSOLETE: deprecated, kept for reader compatibility only
vsn.REC_STORAGE_POLICY   = 0x0009  -- StoragePolicy record type (authoritative on wire)
vsn.REC_REPRESENTATION_DESCRIPTOR = 0x0008

-- Storage Policy values -- authoritative classification (directly on wire)
vsn.STORAGE_HIGHLY_VERTICAL    = 1
vsn.STORAGE_VERTICAL           = 2
vsn.STORAGE_HORIZONTAL         = 3
vsn.STORAGE_HIGHLY_HORIZONTAL  = 4

vsn.FID_RECORDS_END = 0x0000
vsn.FID_FILE_ID = 0x0101
vsn.FID_REV_ID = 0x0201
vsn.FID_REV_FILE_ID = 0x0202
vsn.FID_REV_OBJECT_SERIAL = 0x0203
vsn.FID_REV_PATH = 0x0210
vsn.FID_REV_PRESENCE = 0x0211
vsn.FID_HEAD_FILE_ID = 0x0401
vsn.FID_HEAD_REV_ID = 0x0402
vsn.FID_OBJECT_SERIAL = 0x0501
vsn.FID_OBJECT_SIZE = 0x0511
vsn.FID_COMMIT_GENERATION = 0x0601
vsn.FID_MODE = 0x0701

vsn.MODE_MODERN = 0x01
vsn.MODE_ENTERPRISE = 0x02

vsn.REP_DIRECT_1 = 0x0001
vsn.REP_EXTENTS_1 = 0x0002
vsn.REP_VERSION_1 = 1

vsn.PRESENT = 1
vsn.DELETED = 2
vsn.DIRECTORY = 3

-- -- Writer Storage Policy (informative, NOT on wire) --
vsn.STORAGE_POLICY_HIGHLY_VERTICAL   = 1
vsn.STORAGE_POLICY_VERTICAL         = 2
vsn.STORAGE_POLICY_HORIZONTAL       = 3
vsn.STORAGE_POLICY_HIGHLY_HORIZONTAL = 4

-- Storage Policy record type and field ID (new)
vsn.FID_STORAGE_POLICY       = 0x0901

vsn.OP_LITERAL_BYTES = 0
vsn.OP_OBJECT_SOURCE = 1
vsn.OP_NUMERIC = 2
vsn.OP_NESTED = 3

-- ---------------------------------------------------------------------------
-- Primitives (GR-08, GR-21..GR-26). Big-endian; minimal LEB128 uvarint.
-- ---------------------------------------------------------------------------
vsn.MAGIC = "VSN-"

local function put_u16(v)
  if v < 0 or v > 0xFFFF then vsn.fail(0x0001, "u16 out of range") end
  return string.char(v >> 8, v & 0xFF)
end

local function put_uvarint(v)
  if v < 0 then vsn.fail(0x0001, "uvarint negative") end
  local out = {}
  while v >= 0x80 do
    out[#out + 1] = string.char((v & 0x7F) | 0x80)
    v = v >> 7
  end
  out[#out + 1] = string.char(v)
  if #out > 10 then vsn.fail(0x0001, "uvarint exceeds 10 bytes") end
  return table.concat(out)
end

vsn.put_u16 = put_u16
vsn.put_uvarint = put_uvarint

-- Cursor: bounds-checked reads; distinguishes truncation from malformed.
local Cursor = {}
Cursor.__index = Cursor

function Cursor.new(data, pos)
  return setmetatable({ data = data, pos = pos or 1 }, Cursor)
end

function Cursor:remaining() return #self.data - self.pos + 1 end

function Cursor:_need(n)
  if self:remaining() < n then
    vsn.fail(0x0002, string.format("need %d bytes, %d remain", n, self:remaining()))
  end
end

function Cursor:read(n)
  self:_need(n)
  local out = self.data:sub(self.pos, self.pos + n - 1)
  self.pos = self.pos + n
  return out
end

function Cursor:read_u16()
  local a, b = string.byte(self:read(2), 1, 2)
  return (a << 8) | b
end

-- Minimal LEB128 (GR-21/24/25). 10th byte may only be 0x01 (adds 2^63);
-- a trailing zero group is non-minimal and rejected.
function Cursor:read_uvarint()
  local value, shift = 0, 0
  for idx = 0, 9 do
    local b = string.byte(self:read(1), 1)
    if idx == 9 then
      if b == 0x01 then return value + (1 << 63) end
      vsn.fail(0x0001, "uvarint 10th byte invalid")
    end
    value = value | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 then
      if b == 0 and shift > 0 then vsn.fail(0x0001, "non-minimal uvarint") end
      return value
    end
    shift = shift + 7
  end
end

vsn.Cursor = Cursor

-- ---------------------------------------------------------------------------
-- Container parser: streaming, framing-exact, mode-independent (GR-29..33).
-- ---------------------------------------------------------------------------
local function parse_fields(cursor)
  local fields, last = {}, -1
  while cursor:remaining() > 0 do
    local start = cursor.pos
    local fid = cursor:read_u16()
    local ln = cursor:read_uvarint()
    local val = cursor:read(ln)
    if fid <= last then
      vsn.fail(0x0011, string.format("FieldId %d not strictly ascending", fid))
    end
    last = fid
    fields[#fields + 1] = { fid = fid, value = val, offset = start }
  end
  return fields
end

local function field_of(fields, fid)
  for i = 1, #fields do
    if fields[i].fid == fid then return fields[i] end
  end
  return nil
end

local function field_uvarint(f)
  if f == nil then return nil end
  return Cursor.new(f.value):read_uvarint()
end

local function parse_container(data)
  local cur = Cursor.new(data)
  if cur:remaining() < 4 or cur:read(4) ~= vsn.MAGIC then
    vsn.fail(0x0001, "bad magic")
  end
  local cfv = cur:read_u16()
  if cfv ~= 1 then vsn.fail(0x0003, "unsupported container format version " .. cfv) end
  local ev = cur:read_u16()
  if ev ~= 1 then vsn.fail(0x0004, "unsupported encoding version " .. ev) end

  while true do
    local fid = cur:read_u16()
    local ln = cur:read_uvarint()
    if fid == vsn.FID_RECORDS_END then
      if ln ~= 0 then vsn.fail(0x0001, "RecordsEnd length must be 0") end
      break
    end
    cur:read(ln)
  end

  local records = {}
  while true do
    local start = cur.pos
    local rt = cur:read_u16()
    if rt == vsn.REC_END_OF_RECORDS then break end
    local rl = cur:read_uvarint()
    local payload = cur:read(rl)
    local rec = { rtype = rt, payload = payload, fields = {}, offset = start }
    -- REC_STORAGE_POLICY (0x0009) is a canonical field-bearing record; it MUST be
    -- included in field parsing or the writer's storage policy is lost on read-back.
    if rt <= vsn.REC_STORAGE_POLICY then
      rec.fields = parse_fields(Cursor.new(payload))
    end
    records[#records + 1] = rec
  end

  local objects = {}
  while true do
    local start = cur.pos
    local serial = cur:read_uvarint()
    if serial == 0 then break end
    local ol = cur:read_uvarint()
    local desc = cur:read(ol)
    objects[#objects + 1] = { serial = serial, length = ol, descriptor = desc, offset = start }
  end

  local rc = cur:read_uvarint()
  local gen = cur:read_uvarint()

  local cont = {
    container_format_version = cfv, encoding_version = ev,
    records = records, objects = objects,
    trailer_record_count = rc, trailer_generation = gen,
    mode = nil, byte_length = #data,
  }
  for i = 1, #records do
    if records[i].rtype == vsn.REC_MODE_DECLARATION then
      local m = field_of(records[i].fields, vsn.FID_MODE)
      if m and #m.value > 0 then cont.mode = string.byte(m.value, 1) end
    elseif records[i].rtype == vsn.REC_STORAGE_POLICY then
      local sp = field_of(records[i].fields, vsn.FID_STORAGE_POLICY)
      if sp and #sp.value > 0 then cont.storage_policy = string.byte(sp.value, 1) end
    end
  end
  return cont
end
vsn.parse = parse_container
vsn.field_of = field_of
vsn.field_uvarint = field_uvarint
vsn.parse_fields = parse_fields

-- ---------------------------------------------------------------------------
-- Canonical writer (encoder)
-- ---------------------------------------------------------------------------
local function field_bytes(fid, value)
  return put_u16(fid) .. put_uvarint(#value) .. value
end

local function record_bytes(rtype, fields)
  local payload = {}
  for i = 1, #fields do
    payload[i] = field_bytes(fields[i].fid, fields[i].value)
  end
  payload = table.concat(payload)
  return put_u16(rtype) .. put_uvarint(#payload) .. payload
end

-- encode(records, objects, generation) -> canonical bytes
-- records: { {rtype=, fields={fid,value}}, ... }   objects: {serial, descriptor}
function vsn.encode(records, objects, generation)
  local out = { vsn.MAGIC, put_u16(1), put_u16(1) }
  out[#out + 1] = field_bytes(vsn.FID_RECORDS_END, "")
  for i = 1, #records do
    out[#out + 1] = record_bytes(records[i].rtype, records[i].fields)
  end
  out[#out + 1] = put_u16(vsn.REC_END_OF_RECORDS)
  for i = 1, #objects do
    out[#out + 1] = put_uvarint(objects[i][1]) .. put_uvarint(#objects[i][2]) .. objects[i][2]
  end
  out[#out + 1] = put_uvarint(0)
  local canonical_count = 0
  for i = 1, #records do
    if records[i].rtype ~= vsn.REC_STORAGE_POLICY then canonical_count = canonical_count + 1 end
  end
  out[#out + 1] = put_uvarint(canonical_count)
  out[#out + 1] = put_uvarint(generation)
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Representations: DIRECT-1 and EXTENTS-1 (DR-0..DR-12)
-- ---------------------------------------------------------------------------
local materialize_operation
local _apply_operation

function vsn.parse_object_header(descriptor)
  local c = Cursor.new(descriptor)
  local ident = c:read_u16()
  local ver = c:read_uvarint()
  return ident, ver, descriptor:sub(c.pos)
end

local function materialize_extents(remainder, resolve)
  local c = Cursor.new(remainder)
  local op_count = c:read_uvarint()
  local out = {}
  for _ = 1, op_count do
    out[#out + 1] = materialize_operation(c, resolve)
  end
  if c:remaining() ~= 0 then
    vsn.fail(0x000C, "trailing bytes after EXTENTS-1 operations")
  end
  return table.concat(out)
end

local function read_operand(c)
  local kind = c:read_uvarint()
  if kind == vsn.OP_LITERAL_BYTES then
    local ln = c:read_uvarint()
    return { kind = "lit", value = c:read(ln) }
  end
  if kind == vsn.OP_OBJECT_SOURCE then
    return { kind = "src", value = c:read_uvarint() }
  end
  if kind == vsn.OP_NUMERIC then
    return { kind = "num", value = c:read_uvarint() }
  end
  if kind == vsn.OP_NESTED then
    local n = c:read_uvarint()
    local ops = {}
    for _ = 1, n do ops[#ops + 1] = read_operand(c) end
    return { kind = "nested", value = ops }
  end
  vsn.fail(0x0006, "unknown operand kind " .. kind)
end

materialize_operation = function(c, resolve, visited)
  local kind = c:read_uvarint()
  if kind ~= vsn.OP_NESTED then
    vsn.fail(0x000C, "operation must be NESTED, got kind " .. kind)
  end
  local n = c:read_uvarint()
  local operands = {}
  for _ = 1, n do operands[#operands + 1] = read_operand(c) end
  return _apply_operation(operands, resolve, visited)
end

local function direct1_descriptor(content)
  return put_u16(vsn.REP_DIRECT_1) .. put_uvarint(vsn.REP_VERSION_1) .. content
end

vsn.direct1_descriptor = direct1_descriptor
vsn.materialize_direct = function(rem) return rem end
vsn.materialize_extents = materialize_extents

_apply_operation = function(operands, resolve, visited)
  -- COPY(source, offset, length) = [src, num, num]
  -- LITERAL(bytes) = [lit, num(0)]  (the reserved NUMERIC 0)
  if #operands == 0 then vsn.fail(0x000C, "empty operation") end
  local head = operands[1]
  if head.kind == "src" then
    if #operands ~= 3 or operands[2].kind ~= "num" or operands[3].kind ~= "num" then
      vsn.fail(0x000C, "malformed COPY operation")
    end
    local source = head.value
    local off = operands[2].value
    local length = operands[3].value
    if visited and visited[source] then
      vsn.fail(0x000C, "dependency cycle at ObjectSerial " .. source)
    end
    local src_bytes = resolve(source)
    if off < 0 or length < 0 or off + length > #src_bytes then
      vsn.fail(0x000C, "COPY range out of bounds")
    end
    return src_bytes:sub(off + 1, off + length)
  end
  if head.kind == "lit" then
    return head.value
  end
  vsn.fail(0x000C, "unknown operation head kind " .. tostring(head.kind))
end

-- ---------------------------------------------------------------------------
-- Store: mutable container with the full Library API
-- ---------------------------------------------------------------------------
local Store = {}
Store.__index = Store

local function new_file_id()
  local out = {}
  for i = 1, 16 do out[i] = string.char(math.random(0, 255)) end
  return table.concat(out)
end

function Store.new(data, mode, spolicy)
  local self = setmetatable({}, Store)
  if data ~= nil then
    self.data = data
    self.parsed = vsn.parse(data)
    self.mode = self.parsed.mode or (mode or vsn.MODE_MODERN)
    self.storage_policy = self.parsed.storage_policy or 2 -- default VERTICAL
  else
    self.data = nil
    self.parsed = nil
    self.mode = mode or vsn.MODE_MODERN
    self.storage_policy = spolicy or 2 -- default VERTICAL
  end
  self.closed = false
  self.file_order = {}
  self.file_map = {}
  self.revisions = {}
  self.objects = {}
  self.content_cache = {}
  self.next_object_serial = 1
  self.next_revision_id = 1
  self.generation = 0
  self:build_state()
  return self
end

function Store:build_state()
  self.file_order = {}
  self.file_map = {}
  self.revisions = {}
  self.objects = {}
  self.content_cache = {}
  self.next_object_serial = 1
  self.next_revision_id = 1
  self.generation = 0
  if self.parsed == nil then return end
  for i = 1, #self.parsed.records do
    local rec = self.parsed.records[i]
    if rec.rtype == vsn.REC_FILE_IDENTITY then
      local f = vsn.field_of(rec.fields, vsn.FID_FILE_ID)
      if f then
        self.file_order[#self.file_order + 1] = f.value
        self.file_map[f.value] = { path = nil, head_rev = nil }
      end
    elseif rec.rtype == vsn.REC_REVISION then
      local rid_f = vsn.field_of(rec.fields, vsn.FID_REV_ID)
      local fid_f = vsn.field_of(rec.fields, vsn.FID_REV_FILE_ID)
      local obj_f = vsn.field_of(rec.fields, vsn.FID_REV_OBJECT_SERIAL)
      local path_f = vsn.field_of(rec.fields, vsn.FID_REV_PATH)
      local pres_f = vsn.field_of(rec.fields, vsn.FID_REV_PRESENCE)
      if rid_f and fid_f then
        local rid = vsn.field_uvarint(rid_f)
        local fid = fid_f.value
        self.revisions[rid] = {
          file_id = fid,
          object_serial = obj_f and vsn.field_uvarint(obj_f) or nil,
          path = path_f and path_f.value or nil,
          presence = pres_f and string.byte(pres_f.value, 1) or vsn.PRESENT,
        }
        if rid >= self.next_revision_id then self.next_revision_id = rid + 1 end
        if self.file_map[fid] and path_f then
          self.file_map[fid].path = path_f.value
        end
      end
    elseif rec.rtype == vsn.REC_FILE_HEAD then
      local fid_f = vsn.field_of(rec.fields, vsn.FID_HEAD_FILE_ID)
      local rid_f = vsn.field_of(rec.fields, vsn.FID_HEAD_REV_ID)
      if fid_f and rid_f and self.file_map[fid_f.value] then
        self.file_map[fid_f.value].head_rev = vsn.field_uvarint(rid_f)
      end
    elseif rec.rtype == vsn.REC_COMMIT_MARKER then
      local gen_f = vsn.field_of(rec.fields, vsn.FID_COMMIT_GENERATION)
      if gen_f then self.generation = vsn.field_uvarint(gen_f) end
    elseif rec.rtype == vsn.REC_STORAGE_POLICY then
      local sp = vsn.field_of(rec.fields, vsn.FID_STORAGE_POLICY)
      if sp and #sp.value > 0 then self.storage_policy = string.byte(sp.value, 1) end
    end
  end
  for i = 1, #self.parsed.objects do
    local o = self.parsed.objects[i]
    self.objects[o.serial] = o.descriptor
    if o.serial >= self.next_object_serial then self.next_object_serial = o.serial + 1 end
  end
end


vsn.Store = Store
vsn.create = function(mode) return Store.new(nil, mode or vsn.MODE_MODERN) end

-- Writer Storage Policy chain -- Canonical writer: stores policy directly on wire.
vsn.create_with_storage_policy = function(spolicy)
  local val = spolicy or vsn.STORAGE_VERTICAL
  return Store.new(nil, vsn.MODE_MODERN, val)
end

vsn.open = function(data) return Store.new(data) end

function Store:close()
  self.closed = true
  self.content_cache = {}
end

function Store:check_open()
  if self.closed then vsn.fail(0x0001, "container is closed") end
end

-- --- File API ---

function Store:create_file(path, content)
  self:check_open()
  content = content or ""
  for _, fid in ipairs(self.file_order) do
    if self.file_map[fid].path == path then
      vsn.fail(0x000A, "duplicate path " .. path)
    end
  end
  local file_id = new_file_id()
  self.file_order[#self.file_order + 1] = file_id
  self.file_map[file_id] = { path = path, head_rev = nil }
  local serial = self:_add_object(content)
  local rid = self.next_revision_id
  self.next_revision_id = rid + 1
  self.revisions[rid] = {
    file_id = file_id, object_serial = serial,
    path = path, presence = vsn.PRESENT,
  }
  self.file_map[file_id].head_rev = rid
  return file_id
end

function Store:read_file(file_id)
  self:check_open()
  local info = self.file_map[file_id]
  if info == nil then vsn.fail(0x0009, "unknown FileId") end
  local rid = info.head_rev
  if rid == nil then vsn.fail(0x0009, "no accepted revision") end
  local rev = self.revisions[rid]
  if rev.presence == vsn.DELETED then vsn.fail(0x0009, "file is deleted") end
  if rev.object_serial == nil then return "" end
  return self:materialize(rev.object_serial)
end

function Store:write_file(file_id, content)
  self:check_open()
  local info = self.file_map[file_id]
  if info == nil then vsn.fail(0x0009, "unknown FileId") end
  local serial = self:_add_object(content or "")
  local rid = self.next_revision_id
  self.next_revision_id = rid + 1
  self.revisions[rid] = {
    file_id = file_id, object_serial = serial,
    path = info.path, presence = vsn.PRESENT,
  }
  info.head_rev = rid
end

function Store:delete_file(file_id)
  self:check_open()
  local info = self.file_map[file_id]
  if info == nil then vsn.fail(0x0009, "unknown FileId") end
  local rid = self.next_revision_id
  self.next_revision_id = rid + 1
  self.revisions[rid] = {
    file_id = file_id, object_serial = nil,
    path = info.path, presence = vsn.DELETED,
  }
  info.head_rev = rid
end

function Store:rename_file(file_id, new_path)
  self:check_open()
  local info = self.file_map[file_id]
  if info == nil then vsn.fail(0x0009, "unknown FileId") end
  for _, fid in ipairs(self.file_order) do
    if fid ~= file_id and self.file_map[fid].path == new_path then
      vsn.fail(0x000A, "duplicate path " .. new_path)
    end
  end
  local old_rev = self.revisions[info.head_rev] or {}
  local new_rid = self.next_revision_id
  self.next_revision_id = new_rid + 1
  self.revisions[new_rid] = {
    file_id = file_id,
    object_serial = old_rev.object_serial,
    path = new_path,
    presence = old_rev.presence or vsn.PRESENT,
  }
  info.head_rev = new_rid
  info.path = new_path
end

function Store:list_files()
  self:check_open()
  local out = {}
  for _, fid in ipairs(self.file_order) do
    out[#out + 1] = { file_id = fid, path = self.file_map[fid].path }
  end
  return out
end

function Store:file_exists(file_id)
  self:check_open()
  local info = self.file_map[file_id]
  if info == nil then return false end
  local rid = info.head_rev
  if rid == nil then return false end
  return self.revisions[rid].presence ~= vsn.DELETED
end

function Store:get_file_id(path)
  self:check_open()
  for _, fid in ipairs(self.file_order) do
    if self.file_map[fid].path == path then return fid end
  end
  return nil
end

-- --- Revision API ---

function Store:list_revisions(file_id)
  self:check_open()
  local rids = {}
  for rid in pairs(self.revisions) do
    if file_id == nil or self.revisions[rid].file_id == file_id then
      rids[#rids + 1] = rid
    end
  end
  table.sort(rids)
  return rids
end

function Store:get_revision(revision_id)
  self:check_open()
  local rev = self.revisions[revision_id]
  if rev == nil then vsn.fail(0x0009, "unknown RevisionId " .. revision_id) end
  local out = {
    file_id = rev.file_id, object_serial = rev.object_serial,
    path = rev.path, presence = rev.presence, revision_id = revision_id,
  }
  return out
end

function Store:get_current_revision(file_id)
  self:check_open()
  local info = self.file_map[file_id]
  if info == nil then return nil end
  return info.head_rev
end

function Store:checkout_revision(file_id, revision_id)
  self:check_open()
  local rev = self.revisions[revision_id]
  if rev == nil then vsn.fail(0x0009, "unknown RevisionId " .. revision_id) end
  if rev.file_id ~= file_id then
    vsn.fail(0x000B, "RevisionId does not belong to FileId")
  end
  if rev.object_serial == nil then return "" end
  return self:materialize(rev.object_serial)
end

function Store:restore_revision(file_id, revision_id)
  self:check_open()
  local rev = self.revisions[revision_id]
  if rev == nil then vsn.fail(0x0009, "unknown RevisionId " .. revision_id) end
  if rev.file_id ~= file_id then
    vsn.fail(0x000B, "RevisionId does not belong to FileId")
  end
  local content = rev.object_serial and self:materialize(rev.object_serial) or ""
  self:write_file(file_id, content)
end
-- --- History retention: LimitCleanUp (closed contract, per FileId) ---
--
-- Retain the newest `limit` revisions of one file. limit MUST be >= 1
-- (limit 0 -> 0x000C). Removed revisions are unavailable (0x0009). Objects are
-- NOT garbage-collected. Idempotent, atomic, monotonic, per-file isolated.
function Store:limit_cleanup(file_id, limit)
  self:check_open()
  if limit < 1 then
    vsn.fail(0x000C, "LimitCleanUp limit must be >= 1, got " .. limit)
  end
  if self.file_map[file_id] == nil then vsn.fail(0x0009, "unknown FileId") end

  -- Filter by FileId BEFORE ordering; ordering is ascending RevisionId.
  local rids = {}
  for rid in pairs(self.revisions) do
    if self.revisions[rid].file_id == file_id then rids[#rids + 1] = rid end
  end
  table.sort(rids)
  if #rids <= limit then return {} end
  local keep = {}
  for i = #rids - limit + 1, #rids do keep[rids[i]] = true end
  local removed = {}
  for _, rid in ipairs(rids) do
    if not keep[rid] then removed[#removed + 1] = rid end
  end

  local head = self.file_map[file_id].head_rev
  if head ~= nil and not keep[head] then
    vsn.fail(0x000C, "LimitCleanUp would remove head revision " .. head)
  end

  -- Apply atomically: snapshot, mutate, roll back on any failure.
  local snapshot = {}
  for rid, rev in pairs(self.revisions) do snapshot[rid] = rev end
  local cache_snapshot = self.content_cache
  local ok, err = pcall(function()
    for _, rid in ipairs(removed) do self.revisions[rid] = nil end
    self.content_cache = {}
  end)
  if not ok then
    self.revisions = snapshot
    self.content_cache = cache_snapshot
    if type(err) == "table" and err.code then error(err, 0) end
    vsn.fail(0x000C, "cleanup failed: " .. tostring(err))
  end
  return removed
end

-- --- Object API ---

function Store:_add_object(content)
  local serial = self.next_object_serial
  self.next_object_serial = serial + 1
  self.objects[serial] = direct1_descriptor(content)
  return serial
end

function Store:get_object_serial(file_id, revision_id)
  self:check_open()
  if self.file_map[file_id] == nil then vsn.fail(0x0009, "unknown FileId") end
  local rid = revision_id
    or (self.file_map[file_id].head_rev)
  if rid == nil then return nil end
  local rev = self.revisions[rid]
  if rev == nil then return nil end
  return rev.object_serial
end

function Store:list_objects()
  self:check_open()
  local serials = {}
  for serial in pairs(self.objects) do serials[#serials + 1] = serial end
  table.sort(serials)
  return serials
end

function Store:get_object_info(serial)
  self:check_open()
  local desc = self.objects[serial]
  if desc == nil then vsn.fail(0x0008, "missing object " .. serial) end
  local ident, ver, rem = vsn.parse_object_header(desc)
  return {
    serial = serial, length = #rem,
    representation_identity = ident,
    representation_version = ver,
  }
end

function Store:materialize(serial, visited)
  self:check_open()
  if visited == nil then visited = {} end
  if visited[serial] then
    vsn.fail(0x000C, "cycle at ObjectSerial " .. serial)
  end
  if self.content_cache[serial] ~= nil then
    return self.content_cache[serial]
  end
  local desc = self.objects[serial]
  if desc == nil then vsn.fail(0x0008, "missing object " .. serial) end
  local ident, ver, rem = vsn.parse_object_header(desc)
  local out
  if ident == vsn.REP_DIRECT_1 and ver == vsn.REP_VERSION_1 then
    out = vsn.materialize_direct(rem)
  elseif ident == vsn.REP_EXTENTS_1 and ver == vsn.REP_VERSION_1 then
    local child_visited = visited
    child_visited[serial] = true
    out = vsn.materialize_extents(rem, function(s)
      return self:materialize(s, child_visited)
    end)
  else
    vsn.fail(0x0006, string.format("unsupported rep 0x%04X v%d", ident, ver))
  end
  self.content_cache[serial] = out
  return out
end

-- --- Container lifecycle ---

function Store:to_bytes()
  self:check_open()
  self.generation = self.generation + 1
  local records = {}
  -- Storage Policy (canonical) -- REC_STORAGE_POLICY with FID_STORAGE_POLICY
  records[#records + 1] = {
    rtype = vsn.REC_STORAGE_POLICY,
    fields = { { fid = vsn.FID_STORAGE_POLICY, value = string.char(self.storage_policy) } },
  }
  for _, fid in ipairs(self.file_order) do
    records[#records + 1] = {
      rtype = vsn.REC_FILE_IDENTITY,
      fields = { { fid = vsn.FID_FILE_ID, value = fid } },
    }
  end
  local rids = {}
  for rid in pairs(self.revisions) do rids[#rids + 1] = rid end
  table.sort(rids)
  for _, rid in ipairs(rids) do
    local rev = self.revisions[rid]
    local fields = {
      { fid = vsn.FID_REV_ID, value = put_uvarint(rid) },
      { fid = vsn.FID_REV_FILE_ID, value = rev.file_id },
    }
    if rev.object_serial ~= nil then
      fields[#fields + 1] = { fid = vsn.FID_REV_OBJECT_SERIAL, value = put_uvarint(rev.object_serial) }
    end
    if rev.path ~= nil then
      fields[#fields + 1] = { fid = vsn.FID_REV_PATH, value = rev.path }
    end
    fields[#fields + 1] = { fid = vsn.FID_REV_PRESENCE, value = string.char(rev.presence) }
    records[#records + 1] = { rtype = vsn.REC_REVISION, fields = fields }
  end
  local serials = {}
  for serial in pairs(self.objects) do serials[#serials + 1] = serial end
  table.sort(serials)
  for _, serial in ipairs(serials) do
    local fields = { { fid = vsn.FID_OBJECT_SERIAL, value = put_uvarint(serial) } }
    -- 0x0511 is the LOGICAL content length (SR-27, DR-6), optional.
    local ok, content = pcall(function() return self:materialize(serial) end)
    if ok then
      fields[#fields + 1] = { fid = vsn.FID_OBJECT_SIZE, value = put_uvarint(#content) }
    end
    records[#records + 1] = { rtype = vsn.REC_CONTENT_OBJECT, fields = fields }
  end
  for _, fid in ipairs(self.file_order) do
    local rid = self.file_map[fid].head_rev
    if rid ~= nil then
      records[#records + 1] = {
        rtype = vsn.REC_FILE_HEAD,
        fields = {
          { fid = vsn.FID_HEAD_FILE_ID, value = fid },
          { fid = vsn.FID_HEAD_REV_ID, value = put_uvarint(rid) },
        },
      }
    end
  end
  records[#records + 1] = {
    rtype = vsn.REC_COMMIT_MARKER,
    fields = { { fid = vsn.FID_COMMIT_GENERATION, value = put_uvarint(self.generation) } },
  }
  local objects = {}
  for _, serial in ipairs(serials) do objects[#objects + 1] = { serial, self.objects[serial] } end
  return vsn.encode(records, objects, self.generation)
end

function Store:commit()
  self:check_open()
  local data = self:to_bytes()
  self.data = data
  self.parsed = vsn.parse(data)
  self.content_cache = {}
  self:build_state()
  return data
end

function Store:reopen(data)
  self:check_open()
  if data == nil then data = self.data end
  self.data = data
  self.parsed = vsn.parse(data)
  self.content_cache = {}
  self:build_state()
  return self.generation
end

function Store:inspect()
  self:check_open()
  local file_count = #self.file_order
  local revision_count = 0
  for _ in pairs(self.revisions) do revision_count = revision_count + 1 end
  local object_count = 0
  for _ in pairs(self.objects) do object_count = object_count + 1 end
  return {
    mode = self.mode,
    generation = self.generation,
    file_count = file_count,
    revision_count = revision_count,
    object_count = object_count,
  }
end

-- ---------------------------------------------------------------------------
-- Transactions: staging, precondition, commit (CommitMarker is the sole
-- acceptance authority; ExpectedRevisionId is a precondition, never persisted)
-- ---------------------------------------------------------------------------
local Transaction = {}
Transaction.__index = Transaction

function Transaction.new(expected_revision_id)
  return setmetatable({
    expected_revision_id = expected_revision_id,
    staged = {},
    committed = false,
  }, Transaction)
end

function Transaction:stage_create(path, content)
  self.staged[#self.staged + 1] = { op = "create", path = path, content = content or "" }
end

function Transaction:stage_update(file_id, content)
  self.staged[#self.staged + 1] = { op = "update", file_id = file_id, content = content }
end

function Transaction:stage_delete(file_id)
  self.staged[#self.staged + 1] = { op = "delete", file_id = file_id }
end

function Transaction:stage_rename(file_id, new_path)
  self.staged[#self.staged + 1] = { op = "rename", file_id = file_id, new_path = new_path }
end

function Transaction:inspect()
  local out = {}
  for _, c in ipairs(self.staged) do
    out[#out + 1] = {
      op = c.op, file_id = c.file_id, path = c.path, new_path = c.new_path,
    }
  end
  return out
end

function Transaction:rollback()
  self.staged = {}
end

function Transaction:commit(store)
  if self.committed then vsn.fail(0x000C, "transaction already committed") end
  if self.expected_revision_id ~= nil then
    for _, change in ipairs(self.staged) do
      if change.file_id ~= nil then
        local current = store:get_current_revision(change.file_id)
        if current ~= self.expected_revision_id then
          vsn.fail(0x000D, string.format(
            "ExpectedRevisionId mismatch: expected %d, got %s",
            self.expected_revision_id, tostring(current)))
        end
        break
      end
    end
  end
  for _, change in ipairs(self.staged) do
    if change.op == "create" then
      store:create_file(change.path, change.content)
    elseif change.op == "update" then
      store:write_file(change.file_id, change.content)
    elseif change.op == "delete" then
      store:delete_file(change.file_id)
    elseif change.op == "rename" then
      store:rename_file(change.file_id, change.new_path)
    end
  end
  self.committed = true
  return store:commit()
end

vsn.Transaction = Transaction

-- ---------------------------------------------------------------------------
-- Builder API: incremental canonical container construction
-- ---------------------------------------------------------------------------
local Builder = {}
Builder.__index = Builder

function Builder.new(mode)
  local self = setmetatable({
    mode = mode or vsn.MODE_MODERN,
    records = {},
    objects = {},
    file_ids = {},
    revision_ids = {},
    object_serials = {},
    next_object_serial = 1,
  }, Builder)
  return self
end

-- logical content of a descriptor within this builder's object set
function Builder:_logical_content(descriptor, visited)
  if visited == nil then visited = {} end
  if visited[descriptor] then vsn.fail(0x000C, "dependency cycle") end
  visited[descriptor] = true
  local ident, ver, rem = vsn.parse_object_header(descriptor)
  if ident == vsn.REP_DIRECT_1 and ver == vsn.REP_VERSION_1 then
    return vsn.materialize_direct(rem)
  end
  if ident == vsn.REP_EXTENTS_1 and ver == vsn.REP_VERSION_1 then
    local resolve = function(s)
      for i = 1, #self.objects do
        if self.objects[i][1] == s then
          return self:_logical_content(self.objects[i][2], visited)
        end
      end
      vsn.fail(0x0008, "missing object " .. s)
    end
    return vsn.materialize_extents(rem, resolve)
  end
  vsn.fail(0x0006, string.format("unsupported representation 0x%04X v%d", ident, ver))
end

function Builder:add_file(file_id)
  if #file_id ~= 16 then vsn.fail(0x0001, "FileId must be 16 bytes") end
  if self.file_ids[file_id] then vsn.fail(0x000A, "duplicate FileId") end
  self.file_ids[file_id] = true
  self.records[#self.records + 1] = {
    rtype = vsn.REC_FILE_IDENTITY,
    fields = { { fid = vsn.FID_FILE_ID, value = file_id } },
  }
  return self
end

function Builder:add_object(content, serial)
  if serial == nil then
    serial = self.next_object_serial
    self.next_object_serial = serial + 1
  end
  if self.object_serials[serial] then vsn.fail(0x000A, "duplicate ObjectSerial") end
  self.object_serials[serial] = true
  self.records[#self.records + 1] = {
    rtype = vsn.REC_CONTENT_OBJECT,
    fields = {
      { fid = vsn.FID_OBJECT_SERIAL, value = put_uvarint(serial) },
      { fid = vsn.FID_OBJECT_SIZE, value = put_uvarint(#content) },
    },
  }
  self.objects[#self.objects + 1] = { serial, direct1_descriptor(content) }
  return serial
end

-- add a raw descriptor (e.g. EXTENTS-1); 0x0511 = logical length, omitted if
-- it cannot be resolved (SR-27: optional)
function Builder:add_object_raw(descriptor, serial)
  if self.object_serials[serial] then vsn.fail(0x000A, "duplicate ObjectSerial") end
  self.object_serials[serial] = true
  if serial >= self.next_object_serial then self.next_object_serial = serial + 1 end
  self.objects[#self.objects + 1] = { serial, descriptor }
  local fields = { { fid = vsn.FID_OBJECT_SERIAL, value = put_uvarint(serial) } }
  local ok, content = pcall(function() return self:_logical_content(descriptor) end)
  if ok then
    fields[#fields + 1] = { fid = vsn.FID_OBJECT_SIZE, value = put_uvarint(#content) }
  end
  self.records[#self.records + 1] = { rtype = vsn.REC_CONTENT_OBJECT, fields = fields }
  return serial
end

function Builder:add_revision(revision_id, file_id, object_serial, path, presence)
  if object_serial ~= nil and self.object_serials[object_serial] == nil then
    vsn.fail(0x0008, "missing object " .. object_serial)
  end
  self.revision_ids[revision_id] = true
  local fields = {
    { fid = vsn.FID_REV_ID, value = put_uvarint(revision_id) },
    { fid = vsn.FID_REV_FILE_ID, value = file_id },
  }
  if object_serial ~= nil then
    fields[#fields + 1] = { fid = vsn.FID_REV_OBJECT_SERIAL, value = put_uvarint(object_serial) }
  end
  if path ~= nil then fields[#fields + 1] = { fid = vsn.FID_REV_PATH, value = path } end
  if presence ~= nil then
    fields[#fields + 1] = { fid = vsn.FID_REV_PRESENCE, value = string.char(presence) }
  end
  self.records[#self.records + 1] = { rtype = vsn.REC_REVISION, fields = fields }
  return self
end

function Builder:add_head(file_id, revision_id)
  self.records[#self.records + 1] = {
    rtype = vsn.REC_FILE_HEAD,
    fields = {
      { fid = vsn.FID_HEAD_FILE_ID, value = file_id },
      { fid = vsn.FID_HEAD_REV_ID, value = put_uvarint(revision_id) },
    },
  }
  return self
end

function Builder:add_commit(generation)
  self.records[#self.records + 1] = {
    rtype = vsn.REC_COMMIT_MARKER,
    fields = { { fid = vsn.FID_COMMIT_GENERATION, value = put_uvarint(generation) } },
  }
  return self
end

function Builder:build()
  local records = {}
  records[#records + 1] = {
    rtype = vsn.REC_MODE_DECLARATION,
    fields = { { fid = vsn.FID_MODE, value = string.char(self.mode) } },
  }
  for i = 1, #self.records do records[#records + 1] = self.records[i] end
  return vsn.encode(records, self.objects, 1)
end

function Builder:finish()
  return self:build()
end

vsn.Builder = Builder

-- ---------------------------------------------------------------------------
-- Diff: revision pair comparison (byte-exact, no text assumptions)
-- ---------------------------------------------------------------------------
local function lines_of(content)
  local lines, current, i = {}, "", 1
  while true do
    local j = string.find(content, "\n", i, true)
    if j == nil then break end
    lines[#lines + 1] = string.sub(content, i, j - 1)
    i = j + 1
  end
  lines[#lines + 1] = string.sub(content, i)
  return lines
end

local function longest_common_subsequence_len(a, b)
  local la, lb = #a, #b
  if la * lb > 1000000 then
    -- Fallback: count common lines (multiset) for huge inputs.
    local seen = {}
    local common = 0
    for i = 1, la do
      seen[a[i]] = (seen[a[i]] or 0) + 1
    end
    for i = 1, lb do
      if seen[b[i]] then common = common + 1 end
    end
    return common
  end
  local dp = {}
  for i = 1, la do dp[i] = {} end
  for i = la, 1, -1 do
    for j = lb, 1, -1 do
      if a[i] == b[j] then
        dp[i][j] = (dp[i + 1] and dp[i + 1][j + 1] or 0) + 1
      else
        dp[i][j] = math.max(dp[i + 1] and dp[i + 1][j] or 0, dp[i] and dp[i][j + 1] or 0)
      end
    end
  end
  return dp[1] and dp[1][1] or 0
end

function vsn.diff(base, current)
  if base == current then
    return { is_empty = true, additions = 0, deletions = 0, similarity = 1.0, line_additions = 0, line_deletions = 0 }
  end
  local base_lines = lines_of(base)
  local curr_lines = lines_of(current)
  local lcs = longest_common_subsequence_len(base_lines, curr_lines)
  local additions = #curr_lines - lcs
  local deletions = #base_lines - lcs
  local similarity = (#base_lines + #curr_lines > 0)
    and (2 * lcs / (#base_lines + #curr_lines)) or 1.0
  return {
    is_empty = false,
    additions = additions, deletions = deletions,
    similarity = similarity,
    line_additions = additions, line_deletions = deletions,
  }
end

-- Merge: 3-way line-level merge. A line changed identically on both sides is
-- taken once; changed on one side is taken from that side; changed *differently*
-- on both sides is a conflict (0x000F, never guessed).
function vsn.three_way_merge(base, left, right)
  if left == right then return left, false end
  local base_l, left_l, right_l = lines_of(base), lines_of(left), lines_of(right)
  local n = math.max(#base_l, #left_l, #right_l)
  local MISSING = "\x00__vsn_missing__"
  local function line(l, i) return (l[i] or MISSING) end
  local merged = {}
  for i = 1, n do
    local b, o, t = line(base_l, i), line(left_l, i), line(right_l, i)
    local o_changed, t_changed = (o ~= b), (t ~= b)
    local v
    if o_changed and t_changed then
      if o == t then v = o else vsn.fail(0x000F, "merge conflict at line " .. i) end
    elseif o_changed then v = o
    elseif t_changed then v = t
    else v = b end
    merged[i] = (v == MISSING) and "" or v
  end
  local content = table.concat(merged, "\n")
  if #merged > 0 and merged[#merged] ~= "" then content = content .. "\n" end
  return content, true
end

-- ---------------------------------------------------------------------------
-- SHA-256 (pure Lua, used by integrity / diagnostics)
-- ---------------------------------------------------------------------------
local SHA_K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function rotr(x, n) return ((x >> n) | ((x & ((1 << n) - 1)) << (32 - n))) & 0xFFFFFFFF end

function vsn.sha256_hex(data)
  local h = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 }
  local len = #data
  data = data .. "\x80"
  while #data % 64 ~= 56 do data = data .. "\x00" end
  local bitlen = len * 8
  data = data .. string.pack(">I8", bitlen & 0xFFFFFFFFFFFFFFFF)
  for off = 1, #data, 64 do
    local w = {}
    for t = 0, 15 do w[t + 1] = string.unpack(">I4", data, off + t * 4) end
    for t = 16, 63 do
      local s0 = rotr(w[t - 14], 7) ~ rotr(w[t - 14], 18) ~ (w[t - 14] >> 3)
      local s1 = rotr(w[t - 1], 17) ~ rotr(w[t - 1], 19) ~ (w[t - 1] >> 10)
      w[t + 1] = (w[t - 15] + s0 + w[t - 6] + s1) & 0xFFFFFFFF
    end
    local a,b,c,d,e,f,g,gh = table.unpack(h)
    for t = 1, 64 do
      local S1 = rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)
      local ch = (e & f) ~ ((~e & 0xFFFFFFFF) & g)
      local t1 = (gh + S1 + ch + SHA_K[t] + w[t]) & 0xFFFFFFFF
      local S0 = rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)
      local mj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = (S0 + mj) & 0xFFFFFFFF
      gh, g, f, e, d, c, b, a = g, f, e, (d + t1) & 0xFFFFFFFF, c, b, a, (t1 + t2) & 0xFFFFFFFF
    end
    h = { (h[1]+a)&0xFFFFFFFF, (h[2]+b)&0xFFFFFFFF, (h[3]+c)&0xFFFFFFFF, (h[4]+d)&0xFFFFFFFF,
          (h[5]+e)&0xFFFFFFFF, (h[6]+f)&0xFFFFFFFF, (h[7]+g)&0xFFFFFFFF, (h[8]+gh)&0xFFFFFFFF }
  end
  local out = {}
  for i = 1, 8 do out[i] = string.format("%08x", h[i]) end
  return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Recovery (RC-01..RC-45): marker-based; incomplete tails tolerated,
-- malformed later data is not.
-- ---------------------------------------------------------------------------
function vsn.recover(data)
  local ok, parsed = pcall(function() return vsn.parse(data) end)
  if not ok then
    if type(parsed) == "table" and parsed.code == 0x0002 then
      return { accepted_generation = 0, recovered = false, tail_present = true, status = "TRUNCATED" }
    end
    return { accepted_generation = 0, recovered = false, tail_present = false, status = "MALFORMED" }
  end
  local markers = {}
  for i = 1, #parsed.records do
    if parsed.records[i].rtype == vsn.REC_COMMIT_MARKER then
      local g = field_of(parsed.records[i].fields, vsn.FID_COMMIT_GENERATION)
      if g then markers[#markers + 1] = vsn.field_uvarint(g) end
    end
  end
  if #markers == 0 then
    return { accepted_generation = 0, recovered = false, tail_present = false, status = "NO_MARKER" }
  end
  local gen = 0
  for i = 1, #markers do if markers[i] > gen then gen = markers[i] end end
  local tail = (parsed.trailer_generation ~= nil and parsed.trailer_generation > 0)
    and parsed.trailer_generation ~= gen or false
  return {
    accepted_generation = gen, recovered = true, tail_present = tail,
    status = "RECOVERED",
  }
end

local function check_mode(parsed)
  local modes, mode_val = 0, nil
  local has_sp = false
  for i = 1, #parsed.records do
    if parsed.records[i].rtype == vsn.REC_MODE_DECLARATION then
      modes = modes + 1
      local f = field_of(parsed.records[i].fields, vsn.FID_MODE)
      if f == nil or #f.value ~= 1 then
        vsn.fail(0x000C, "ModeDeclaration missing mode value")
      end
      mode_val = string.byte(f.value, 1)
    elseif parsed.records[i].rtype == vsn.REC_STORAGE_POLICY then
      has_sp = true
    end
  end
  -- Accept either one ModeDeclaration OR a StoragePolicy record (canonical form)
  if modes ~= 1 and not has_sp then
    vsn.fail(0x000C, "expected exactly one ModeDeclaration or StoragePolicy")
  end
  -- Mode validation: only applies when we have a ModeDeclaration
  if modes == 1 then
  if mode_val ~= vsn.MODE_MODERN and mode_val ~= vsn.MODE_ENTERPRISE then
    vsn.fail(0x0001, string.format("reserved mode value 0x%02X", mode_val))
  end
  if mode_val == vsn.MODE_ENTERPRISE then
    for i = 1, #parsed.objects do
      local ident = vsn.parse_object_header(parsed.objects[i].descriptor)
      if ident == vsn.REP_EXTENTS_1 then
        vsn.fail(0x000C, "ENTERPRISE mode forbids EXTENTS-1 (GR-43)")
      end
    end
  end
  end
end

local function check_identities(parsed)
  local seen_file, seen_rev, seen_obj = {}, {}, {}
  for i = 1, #parsed.records do
    local rec = parsed.records[i]
    if rec.rtype == vsn.REC_FILE_IDENTITY then
      local f = field_of(rec.fields, vsn.FID_FILE_ID)
      if f ~= nil then
        if seen_file[f.value] then vsn.fail(0x000A, "duplicate FileIdentity") end
        seen_file[f.value] = true
      end
    elseif rec.rtype == vsn.REC_REVISION then
      local f = field_of(rec.fields, vsn.FID_REV_ID)
      if f then
        local rid = vsn.field_uvarint(f)
        if seen_rev[rid] then vsn.fail(0x000A, "duplicate RevisionId " .. rid) end
        seen_rev[rid] = true
      end
    elseif rec.rtype == vsn.REC_CONTENT_OBJECT then
      local f = field_of(rec.fields, vsn.FID_OBJECT_SERIAL)
      if f then
        local sid = vsn.field_uvarint(f)
        if seen_obj[sid] then vsn.fail(0x000A, "duplicate ObjectSerial " .. sid) end
        seen_obj[sid] = true
      end
    end
  end
end

local function check_references(parsed)
  local file_ids, obj_ids, rev_ids = {}, {}, {}
  for i = 1, #parsed.records do
    local rec = parsed.records[i]
    if rec.rtype == vsn.REC_FILE_IDENTITY then
      local f = field_of(rec.fields, vsn.FID_FILE_ID)
      if f then file_ids[f.value] = true end
    elseif rec.rtype == vsn.REC_REVISION then
      local f = field_of(rec.fields, vsn.FID_REV_ID)
      if f then rev_ids[vsn.field_uvarint(f)] = true end
    end
  end
  for i = 1, #parsed.objects do obj_ids[parsed.objects[i].serial] = true end
  for i = 1, #parsed.records do
    local rec = parsed.records[i]
    if rec.rtype == vsn.REC_REVISION then
      local f = field_of(rec.fields, vsn.FID_REV_FILE_ID)
      if f == nil or file_ids[f.value] == nil then
        vsn.fail(0x0009, "Revision references missing FileId")
      end
      local o = field_of(rec.fields, vsn.FID_REV_OBJECT_SERIAL)
      if o ~= nil and obj_ids[vsn.field_uvarint(o)] == nil then
        vsn.fail(0x0008, "Revision references missing ObjectSerial")
      end
    elseif rec.rtype == vsn.REC_FILE_HEAD then
      local f = field_of(rec.fields, vsn.FID_HEAD_FILE_ID)
      if f == nil or file_ids[f.value] == nil then
        vsn.fail(0x0009, "FileHead references missing FileId")
      end
      local r = field_of(rec.fields, vsn.FID_HEAD_REV_ID)
      if r == nil or rev_ids[vsn.field_uvarint(r)] == nil then
        vsn.fail(0x0009, "FileHead references missing RevisionId")
      end
    end
  end
end

function vsn.validate_structural(data)
  vsn.parse(data)
end

function vsn.validate_semantic(data)
  local parsed = vsn.parse(data)
  check_mode(parsed)
  check_identities(parsed)
  check_references(parsed)
end

function vsn.validate_content(data)
  local parsed = vsn.parse(data)
  local declared = {}
  for i = 1, #parsed.records do
    local rec = parsed.records[i]
    if rec.rtype == vsn.REC_CONTENT_OBJECT then
      local sf = field_of(rec.fields, vsn.FID_OBJECT_SERIAL)
      local zf = field_of(rec.fields, vsn.FID_OBJECT_SIZE)
      if sf ~= nil and zf ~= nil then
        declared[vsn.field_uvarint(sf)] = vsn.field_uvarint(zf)
      end
    end
  end
  local store = Store.new(data)
  for _, serial in ipairs(store:list_objects()) do
    local content = store:materialize(serial)
    if declared[serial] ~= nil and declared[serial] ~= #content then
      vsn.fail(0x000C, string.format(
        "declared size %d does not match materialized length %d for ObjectSerial %d (DR-6)",
        declared[serial], #content, serial))
    end
  end
  store:close()
end

local function validation_levels(level)
  if level == "Structural" then return { "Structural" } end
  if level == "Semantic" then return { "Structural", "Semantic" } end
  if level == "Recovery" then return { "Structural", "Semantic", "Recovery" } end
  if level == "Content" then return { "Structural", "Semantic", "Content" } end
  if level == "Full" then
    return { "Structural", "Semantic", "Recovery", "Content" }
  end
  error("unknown validation level " .. tostring(level), 0)
end

function vsn.validate(data, level)
  level = level or "Full"
  for _, lvl in ipairs(validation_levels(level)) do
    if lvl == "Structural" then vsn.validate_structural(data)
    elseif lvl == "Semantic" then vsn.validate_semantic(data)
    elseif lvl == "Recovery" then vsn.recover(data)
    elseif lvl == "Content" then vsn.validate_content(data) end
  end
  return true
end

-- Boolean form: returns false instead of raising on invalid input.
function vsn.validate_ok(data, level)
  return pcall(vsn.validate, data, level)
end
-- ---------------------------------------------------------------------------
-- Structured diagnostics (code, name, severity, category, context)
-- ---------------------------------------------------------------------------
function vsn.validate_with_diagnostics(data, level)
  level = level or "Full"
  local diags = {}
  for _, lvl in ipairs(validation_levels(level)) do
    local fn
    if lvl == "Structural" then fn = vsn.validate_structural
    elseif lvl == "Semantic" then fn = vsn.validate_semantic
    elseif lvl == "Recovery" then fn = function() vsn.recover(data) end
    elseif lvl == "Content" then fn = vsn.validate_content end
    local ok, err = pcall(fn, data)
    if not ok then
      local diag = {
        code = -1, name = "LIBRARY_ERROR", severity = "error",
        category = "library", message = tostring(err), operation = lvl,
      }
      if type(err) == "table" and err.code then
        diag.code = err.code
        diag.name = err.name
        diag.category = "protocol"
      end
      diags[#diags + 1] = diag
      break
    end
  end
  return diags
end

-- ---------------------------------------------------------------------------
-- Derived storage management (indexes / caches; NEVER canonical authority)
-- ---------------------------------------------------------------------------
local StorageManager = {}
StorageManager.__index = StorageManager

function StorageManager.new()
  return setmetatable({
    object_index = {},
    file_index = {},
    content_cache = {},
    valid = false,
  }, StorageManager)
end

function StorageManager:build_indexes(store)
  self.object_index = {}
  self.file_index = {}
  for _, serial in ipairs(store:list_objects()) do
    self.object_index[serial] = store:get_object_info(serial)
  end
  for _, entry in ipairs(store:list_files()) do
    if entry.path ~= nil then self.file_index[entry.path] = entry.file_id end
  end
  self.valid = true
  return self
end

function StorageManager:invalidate()
  self.object_index = {}
  self.file_index = {}
  self.content_cache = {}
  self.valid = false
  return self
end

function StorageManager:rebuild(store)
  self:invalidate()
  return self:build_indexes(store)
end

function StorageManager:gc()
  local n = 0
  for _ in pairs(self.content_cache) do n = n + 1 end
  self.content_cache = {}
  return n
end

function StorageManager:stats(store)
  local record_count = 0
  if store.parsed ~= nil then record_count = #store.parsed.records end
  local revision_count = 0
  for _ in pairs(store.revisions) do revision_count = revision_count + 1 end
  local object_count = 0
  for _ in pairs(store.objects) do object_count = object_count + 1 end
  local index_entries = 0
  for _ in pairs(self.object_index) do index_entries = index_entries + 1 end
  for _ in pairs(self.file_index) do index_entries = index_entries + 1 end
  local cache_entries, cache_bytes = 0, 0
  for _, v in pairs(self.content_cache) do
    cache_entries = cache_entries + 1
    cache_bytes = cache_bytes + #v
  end
  return {
    container_bytes = store.data ~= nil and #store.data or 0,
    record_count = record_count,
    object_count = object_count,
    file_count = #store.file_order,
    revision_count = revision_count,
    index_entries = index_entries,
    cache_entries = cache_entries,
    cache_bytes = cache_bytes,
  }
end

function StorageManager:is_valid()
  return self.valid
end

vsn.StorageManager = StorageManager

-- ---------------------------------------------------------------------------
-- Import / export and streaming I/O (chunk-oriented, byte-oriented)
-- ---------------------------------------------------------------------------
function vsn.import_bytes(store, path, content)
  return store:create_file(path, content or "")
end

function vsn.export_bytes(store, file_id)
  return store:read_file(file_id)
end

function vsn.import_stream(store, path, read_fn, chunk_size)
  -- read_fn(offset, size) -> chunk|nil ; byte-oriented streaming import
  chunk_size = chunk_size or 65536
  local parts = {}
  local offset = 0
  while true do
    local chunk = read_fn(offset, chunk_size)
    if chunk == nil or chunk == "" then break end
    parts[#parts + 1] = chunk
    offset = offset + #chunk
  end
  return store:create_file(path, table.concat(parts))
end

function vsn.export_stream(store, file_id, write_fn, chunk_size)
  -- write_fn(offset, chunk) ; returns total bytes streamed
  chunk_size = chunk_size or 65536
  local content = store:read_file(file_id)
  local total = 0
  local offset = 0
  while offset < #content do
    local chunk = content:sub(offset + 1, math.min(offset + chunk_size, #content))
    write_fn(offset, chunk)
    offset = offset + #chunk
    total = total + #chunk
  end
  return total
end

function vsn.import_multiple(store, files)
  local out = {}
  for path, content in pairs(files) do
    out[path] = store:create_file(path, content or "")
  end
  return out
end

function vsn.export_multiple(store, file_ids)
  local out = {}
  for _, fid in ipairs(file_ids) do
    out[fid] = store:read_file(fid)
  end
  return out
end

-- Filesystem-backed convenience (readable on any platform).
function vsn.read_file_bytes(path)
  local fh, err = io.open(path, "rb")
  if fh == nil then vsn.fail(0x0014, "cannot open " .. path .. ": " .. tostring(err)) end
  local data = fh:read("a")
  fh:close()
  return data
end

function vsn.write_file_bytes(path, data)
  local fh, err = io.open(path, "wb")
  if fh == nil then vsn.fail(0x0014, "cannot open " .. path .. ": " .. tostring(err)) end
  fh:write(data)
  fh:close()
end

-- ---------------------------------------------------------------------------
-- Base64 helpers (interop manifests, JSON payloads)
-- ---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function vsn.b64_encode(data)
  local out = {}
  for i = 1, #data, 3 do
    local a = string.byte(data, i) or 0
    local has_b = string.byte(data, i + 1) ~= nil
    local has_c = string.byte(data, i + 2) ~= nil
    local b = has_b and string.byte(data, i + 1) or 0
    local c = has_c and string.byte(data, i + 2) or 0
    local n = (a << 16) | (b << 8) | c
    local pad = (not has_b) and 2 or ((not has_c) and 1 or 0)
    local i1 = ((n >> 18) & 63) + 1
    local i2 = ((n >> 12) & 63) + 1
    local i3 = ((n >> 6) & 63) + 1
    local i4 = (n & 63) + 1
    out[#out + 1] = B64:sub(i1, i1)
    out[#out + 1] = B64:sub(i2, i2)
    out[#out + 1] = (pad >= 2) and "=" or B64:sub(i3, i3)
    out[#out + 1] = (pad >= 1) and "=" or B64:sub(i4, i4)
  end
  return table.concat(out)
end

local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end
function vsn.b64_decode(s)
  s = s:gsub("[^%w+/=]", "")
  local out = {}
  for i = 1, #s, 4 do
    local a, b = B64_INDEX[s:sub(i, i)], B64_INDEX[s:sub(i + 1, i + 1)]
    local c, d = B64_INDEX[s:sub(i + 2, i + 2)], B64_INDEX[s:sub(i + 3, i + 3)]
    if a == nil or b == nil then break end
    local n = (a << 18) | (b << 12)
    if c ~= nil then n = n | (c << 6) end
    if d ~= nil then n = n | d end
    local part = string.char(
      (n >> 16) & 0xFF,
      (n >> 8) & 0xFF,
      n & 0xFF
    )
    local len = 3
    if c == nil then len = 1 elseif d == nil then len = 2 end
    out[#out + 1] = part:sub(1, len)
  end
  return table.concat(out)
end

return vsn


