-- VSN conformance probe for Lua.
--
-- Invoked by Conformance/run_corpus.sh with one of five subcommands; exits 0
-- only when the check passes. The checks are identical across every language,
-- so a pass here is byte-for-byte conformance with the frozen reference:
--
--   probe.lua vectors   <file> <bytes> <sha256>
--   probe.lua scenario  <file> <interpretation.json>
--   probe.lua limit     <contract.json>
--   probe.lua malformed <frozen_vector>
--   probe.lua interop   <corpus_dir>
--
-- Run manually from the Libraries/Lua directory (require("vsn") resolves there):
--   lua probe.lua vectors ../Conformance/../TestVectors/DIRECT-01.vsn 162 d4c3...
local vsn = require("vsn")

local function read_file(path)
  local fh, err = io.open(path, "rb")
  if not fh then io.stderr:write("cannot open " .. path .. ": " .. tostring(err) .. "\n")
    os.exit(2) end
  local data = fh:read("*a") or ""
  fh:close()
  return data
end

local function fail(msg)
  io.stderr:write(msg .. "\n")
  os.exit(1)
end

local function to_hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- Minimal JSON parser (objects, arrays, strings, numbers, true/false/null).
local function json_parse(text)
  local pos = 1
  local function ws() while pos <= #text and text:sub(pos, pos):match("[%s]") do pos = pos + 1 end end
  local pv, po, pa, ps, pn
  ps = function()
    pos = pos + 1
    local buf = {}
    repeat
      local c = text:sub(pos, pos)
      if c == "" then error("json: unterminated string", 0) end
      if c == "\"" then pos = pos + 1; return table.concat(buf) end
      if c == "\\" then
        local e = text:sub(pos + 1, pos + 1)
        local m = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if e == "u" then buf[#buf + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16)); pos = pos + 6
        else buf[#buf + 1] = m[e]; pos = pos + 2 end
      else
        buf[#buf + 1] = c; pos = pos + 1
      end
    until false
  end
  pn = function()
    local s0 = pos
    while pos <= #text and text:sub(pos, pos):match("[%d%.%-%+eE]") do pos = pos + 1 end
    local n = tonumber(text:sub(s0, pos - 1))
    if n == nil then error("json: bad number", 0) end
    return n
  end
  po = function()
    pos = pos + 1
    local o = {}
    ws()
    if text:sub(pos, pos) == "}" then pos = pos + 1; return o end
    while true do
      ws()
      local k = ps()
      ws()
      if text:sub(pos, pos) ~= ":" then error("json: expected :", 0) end
      pos = pos + 1
      o[k] = pv()
      ws()
      local c = text:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "}" then pos = pos + 1; return o
      else error("json: bad object", 0) end
    end
  end
  pa = function()
    pos = pos + 1
    local a = {}
    ws()
    if text:sub(pos, pos) == "]" then pos = pos + 1; return a end
    while true do
      a[#a + 1] = pv()
      ws()
      local c = text:sub(pos, pos)
      if c == "," then pos = pos + 1
      elseif c == "]" then pos = pos + 1; return a
      else error("json: bad array", 0) end
    end
  end
  pv = function()
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then return po() end
    if c == "[" then return pa() end
    if c == "\"" then return ps() end
    if text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
    if text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
    if text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
    if c:match("[%d%-]") then return pn() end
    error("json: unexpected " .. tostring(c), 0)
  end
  return pv()
end

-- Language-neutral canonical interpretation, matching the recorded corpus JSON.
local function describe(data)
  local parsed = vsn.parse(data)
  local path_by_file, rev_by_file, serial_by_rev = {}, {}, {}
  for i = 1, #parsed.records do
    local rec = parsed.records[i]
    if rec.rtype == vsn.REC_REVISION then
      local rid_f = vsn.field_of(rec.fields, vsn.FID_REV_ID)
      local fid_f = vsn.field_of(rec.fields, vsn.FID_REV_FILE_ID)
      if rid_f and fid_f then
        local key = to_hex(fid_f.value)
        local p = vsn.field_of(rec.fields, vsn.FID_REV_PATH)
        if p then path_by_file[key] = p.value end
        local os_ = vsn.field_of(rec.fields, vsn.FID_REV_OBJECT_SERIAL)
        serial_by_rev[vsn.field_uvarint(rid_f)] = os_ and vsn.field_uvarint(os_) or nil
      end
    elseif rec.rtype == vsn.REC_FILE_HEAD then
      local fid_f = vsn.field_of(rec.fields, vsn.FID_HEAD_FILE_ID)
      local rid_f = vsn.field_of(rec.fields, vsn.FID_HEAD_REV_ID)
      if fid_f and rid_f then rev_by_file[to_hex(fid_f.value)] = vsn.field_uvarint(rid_f) end
    end
  end
  local files = {}
  for i = 1, #parsed.records do
    local rec = parsed.records[i]
    if rec.rtype == vsn.REC_FILE_IDENTITY then
      local fid_f = vsn.field_of(rec.fields, vsn.FID_FILE_ID)
    local key = to_hex(fid_f.value)
    local head = rev_by_file[key]
    local serial = (head ~= nil) and serial_by_rev[head] or nil
    local content, rep_i, rep_v = "", nil, nil
    if serial ~= nil then
      for j = 1, #parsed.objects do
        if parsed.objects[j].serial == serial then
          local ident, ver = vsn.parse_object_header(parsed.objects[j].descriptor)
          rep_i, rep_v = ident, ver
          break
        end
      end
      local st = vsn.open(data)
      content = st:materialize(serial)
      st:close()
    end
    files[#files + 1] = {
      fileId = key, path = path_by_file[key], headRevision = head,
      objectSerial = serial, repIdentity = rep_i, repVersion = rep_v,
      contentBase64 = vsn.b64_encode(content),
    }
  end
  end
  table.sort(files, function(a, b) return a.fileId < b.fileId end)
  local rr = vsn.recover(data)
  return {
    mode = parsed.mode, generation = parsed.trailer_generation,
    recoveryStatus = rr.status, acceptedGeneration = rr.accepted_generation,
    files = files,
  }
end

-- Regenerate a scenario's canonical bytes from this library's own builder.
local function fid(byte) return string.rep(string.char(byte), 16) end

local function extents1_descriptor(operations)
  local out = vsn.put_u16(vsn.REP_EXTENTS_1) .. vsn.put_uvarint(vsn.REP_VERSION_1)
  out = out .. vsn.put_uvarint(#operations)
  for i = 1, #operations do out = out .. operations[i] end
  return out
end

local function literal_op(content)
  return vsn.put_uvarint(vsn.OP_NESTED) .. vsn.put_uvarint(2)
    .. vsn.put_uvarint(vsn.OP_LITERAL_BYTES) .. vsn.put_uvarint(#content) .. content
    .. vsn.put_uvarint(vsn.OP_NUMERIC) .. vsn.put_uvarint(0)
end

local function copy_op(serial, offset, length)
  return vsn.put_uvarint(vsn.OP_NESTED) .. vsn.put_uvarint(3)
    .. vsn.put_uvarint(vsn.OP_OBJECT_SOURCE) .. vsn.put_uvarint(serial)
    .. vsn.put_uvarint(vsn.OP_NUMERIC) .. vsn.put_uvarint(offset)
    .. vsn.put_uvarint(vsn.OP_NUMERIC) .. vsn.put_uvarint(length)
end
local function build_scenario(name)
  local mode, generation = vsn.MODE_MODERN, 1
  if name == "extents" then generation = 2
  elseif name == "enterprise" then mode, generation = vsn.MODE_ENTERPRISE, 1
  elseif name == "multifile" then generation = 3
  elseif name ~= "basic" then fail("unknown scenario " .. name) end
  local b = vsn.Builder.new(mode)
  if name == "basic" then
    local f = fid(0x01)
    b:add_file(f)
    local s = b:add_object("hello vsn\n")
    b:add_revision(1, f, s, "hello.txt", vsn.PRESENT)
    b:add_head(f, 1)
  elseif name == "extents" then
    local a, c = fid(0x02), fid(0x03)
    b:add_file(a)
    b:add_file(c)
    local s1 = b:add_object("hello vsn\n", 1)
    b:add_object_raw(extents1_descriptor({ copy_op(1, 0, 10), literal_op("!!") }), 2)
    b:add_revision(1, a, s1, "a.txt", vsn.PRESENT)
    b:add_revision(2, c, 2, "b.txt", vsn.PRESENT)
    b:add_head(a, 1)
    b:add_head(c, 2)
  elseif name == "enterprise" then
    local f = fid(0x04)
    b:add_file(f)
    local s = b:add_object("enterprise")
    b:add_revision(1, f, s, "e.txt", vsn.PRESENT)
    b:add_head(f, 1)
  elseif name == "multifile" then
    local f1, f2, f3 = fid(0x05), fid(0x06), fid(0x07)
    b:add_file(f1)
    b:add_file(f2)
    b:add_file(f3)
    b:add_object(string.char(0x00, 0x01, 0xFF, 0x00, 0x7F), 1)
    b:add_object("plain text", 2)
    b:add_object("", 3)
    b:add_revision(1, f1, 1, "bin.dat", vsn.PRESENT)
    b:add_revision(2, f2, 2, "text.txt", vsn.PRESENT)
    b:add_revision(3, f3, 3, "empty.txt", vsn.PRESENT)
    b:add_head(f1, 1)
    b:add_head(f2, 2)
    b:add_head(f3, 3)
  else
    fail("unknown scenario " .. name)
  end
  b:add_commit(generation)
  local records = {
    { rtype = vsn.REC_MODE_DECLARATION, fields = { { fid = vsn.FID_MODE, value = string.char(mode) } } },
  }
  for i = 1, #b.records do records[#records + 1] = b.records[i] end
  return vsn.encode(records, b.objects, generation)
end

local function basename(p) return (p:gsub(".*[/\\]", "")) end

local function cmd_vectors(argv)
  local data = read_file(argv[2])
  local want_bytes = tonumber(argv[3])
  if #data ~= want_bytes then fail("length " .. #data .. ", corpus says " .. tostring(want_bytes)) end
  local got = vsn.sha256_hex(data)
  if got ~= argv[4] then fail("sha256 " .. got .. ", corpus says " .. tostring(argv[4])) end
  local parsed = vsn.parse(data)
  if #parsed.records == 0 then fail("no records decoded") end
  local st = vsn.open(data)
  local serials = st:list_objects()
  for i = 1, #serials do
    if st:materialize(serials[i]) == nil then
      fail("object " .. tostring(serials[i]) .. " materialized to nil")
    end
  end
  st:close()
end

local function check_scenario(file, expect_path)
  local data = read_file(file)
  local expected = json_parse(read_file(expect_path))
  local ok, actual = pcall(describe, data)
  if not ok then return false, basename(file) .. " failed to interpret: " .. tostring(actual) end
  if deep_eq(actual, expected) then return true end
  local seen, diffs = {}, {}
  for k in pairs(actual) do seen[k] = true end
  for k in pairs(expected) do seen[k] = true end
  for k in pairs(seen) do
    if not deep_eq(rawget(actual, k), rawget(expected, k)) then
      diffs[#diffs + 1] = k .. ": got " .. tostring(actual[k]) .. " want " .. tostring(expected[k])
    end
  end
  return false, basename(file) .. " interpretation mismatch:\n  " .. table.concat(diffs, "\n  ")
end

local function cmd_scenario(argv)
  local ok, msg = check_scenario(argv[2], argv[3])
  if not ok then fail(msg) end
end

local function code_of(fn) return vsn.code_of(fn) end

local function hist(n)
  local s = vsn.create()
  local f = s:create_file("a.txt", "v1")
  for i = 2, n do s:write_file(f, "v" .. i) end
  return s, f
end

local function eq_list(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function cmd_limit(argv)
  local contract = json_parse(read_file(argv[2]))
  local problems = {}
  local function expect(cond, msg) if not cond then problems[#problems + 1] = msg end end
  for i = 1, #contract.cases do
    local case = contract.cases[i]
    local name = case.name
    if name == "retains_newest_n" then
      local s, f = hist(case.history)
      local removed = s:limit_cleanup(f, case.limit)
      expect(eq_list(removed, case.removed), "removed mismatch")
      expect(eq_list(s:list_revisions(f), case.retained), "retained mismatch")
      expect(s:get_current_revision(f) == case.retained[#case.retained], "FileHead not newest retained")
      local objs_before = #s:list_objects()
      expect(code_of(function() s:get_revision(case.removed[1]) end) == "0009", "removed revision did not raise 0009")
      expect(#s:list_objects() == objs_before, "LimitCleanUp garbage collected objects")
      local data = s:commit()
      local ro = vsn.open(data)
      expect(eq_list(ro:list_revisions(f), case.retained), "cleanup did not persist through commit")
      expect(code_of(function() ro:get_revision(case.removed[1]) end) == "0009", "removed revision resurrected after reopen")
      expect(vsn.recover(data).recovered == true, "recovery failed after cleanup")
      expect(eq_list(ro:limit_cleanup(f, case.limit), {}), "repeat cleanup removed revisions")
      expect(eq_list(ro:limit_cleanup(f, case.limit), {}), "third cleanup removed revisions")
      ro:close()
    elseif name == "limit_zero_rejected" then
      local s, f = hist(case.history)
      expect(code_of(function() s:limit_cleanup(f, 0) end) == "000C", "limit 0 did not raise 000C")
      local full = {}
      for i = 1, case.history do full[i] = i end
      expect(eq_list(s:list_revisions(f), full), "history changed after rejected limit 0")
    elseif name == "limit_greater_than_history" then
      local s, f = hist(case.history)
      local removed = s:limit_cleanup(f, case.limit)
      expect(eq_list(removed, case.removed), "limit>history removed mismatch")
      expect(eq_list(s:list_revisions(f), case.retained), "limit>history retained mismatch")
    elseif name == "idempotent_repeat" then
      local s, f = hist(case.history)
      local first = s:limit_cleanup(f, case.limit)
      expect(eq_list(first, case.removed_first), "first cleanup mismatch")
      expect(eq_list(s:limit_cleanup(f, case.limit), case.removed_second), "second cleanup want empty")
      expect(eq_list(s:limit_cleanup(f, case.limit), case.removed_third), "third cleanup want empty")
    elseif name == "per_file_isolation" then
      local s, f = hist(case.history)
      local other = s:create_file("other.txt", "o1")
      for i = 2, case.history do s:write_file(other, "o" .. i) end
      local before = s:list_revisions(other)
      local before_content = s:read_file(other)
      local removed = s:limit_cleanup(f, case.limit)
      expect(eq_list(removed, case.removed), "isolated cleanup removed mismatch")
      expect(eq_list(s:list_revisions(other), before), "unrelated file history changed")
      expect(s:read_file(other) == before_content, "unrelated file content changed")
    end
  end
  local s = hist(3)
  expect(code_of(function() s:limit_cleanup(string.rep("\0", 16), 5) end) == "0009",
    "unknown FileId did not raise 0009")
  if #problems > 0 then
    fail("LimitCleanUp contract violations:\n  " .. table.concat(problems, "\n  "))
  end
end

local function cmd_malformed(argv)
  local base = read_file(argv[2])
  local problems = {}
  local function expect_code(data, want, label)
    local got = vsn.code_of(function() vsn.parse(data) end)
    if got ~= want then
      problems[#problems + 1] = string.format("%s: got %s want %s", label, got or "no-error", want)
    end
  end
  expect_code(string.char(0x58) .. base:sub(2), "0001", "bad magic")
  expect_code(base:sub(1, 4) .. string.char(0x00, 0x7F) .. base:sub(7), "0003", "bad cfv version")
  expect_code(base:sub(1, 6) .. string.char(0x00, 0x7F) .. base:sub(9), "0004", "bad ev version")
  for n = 0, #base - 1 do
    if vsn.code_of(function() vsn.parse(base:sub(1, n)) end) == nil then
      problems[#problems + 1] = "prefix of length " .. n .. " parsed but must not"
      break
    end
  end
  local intact = vsn.code_of(function() vsn.parse(base) end)
  if intact ~= nil then problems[#problems + 1] = "intact vector failed to parse: " .. intact end
  if #problems > 0 then
    fail("malformed handling wrong:\n  " .. table.concat(problems, "\n  "))
  end
end

local function cmd_interop(argv)
  local root = argv[2]
  local manifest = json_parse(read_file(root .. "/manifest.json"))
  local problems = {}
  for i = 1, #manifest.scenarios do
    local entry = manifest.scenarios[i]
    local name = entry.name
    local path = root .. "/" .. entry.file
    local recorded = read_file(path)
    local ok, produced = pcall(build_scenario, name)
    if not ok then
      problems[#problems + 1] = name .. ": builder failed: " .. tostring(produced)
    elseif produced ~= recorded then
      problems[#problems + 1] = string.format("%s: regenerated %d bytes, corpus has %d",
        name, #produced, #recorded)
    else
      local jok = check_scenario(path, root .. "/scenarios/" .. name .. ".json")
      if not jok then problems[#problems + 1] = name .. ": read-back mismatch" end
    end
  end
  if #problems > 0 then
    fail("interop failures:\n  " .. table.concat(problems, "\n  "))
  end
end
local argv = { ... }
local cmd = argv[1]
local handlers = {
  vectors = cmd_vectors, scenario = cmd_scenario, limit = cmd_limit,
  malformed = cmd_malformed, interop = cmd_interop,
}
if not cmd or not handlers[cmd] then
  print("usage: probe.lua <vectors|scenario|limit|malformed|interop> <inputs>")
  os.exit(2)
end
local ok, err = pcall(handlers[cmd], argv)
if not ok then
  print("FAIL: " .. tostring(err))
  os.exit(1)
end
print("OK: " .. cmd)
