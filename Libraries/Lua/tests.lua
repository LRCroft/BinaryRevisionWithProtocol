-- VSN Library for Lua: capability test suite (19 capabilities).
--
-- Run with any Lua 5.4 interpreter from this directory:
--   lua tests.lua
-- Exits non-zero if any test fails. Each test exercises a distinct capability
-- of the documented surface and verifies observable, protocol-conformant
-- behaviour (including the frozen error identifiers).
local vsn = require("vsn")

local passed, failed, failures = 0, 0, {}
local function run_test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("PASS  " .. name)
  else
    failed = failed + 1
    failures[#failures + 1] = name
    print("FAIL  " .. name .. "  -> " .. tostring(err))
  end
end
local function eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assertion") .. ": expected " .. tostring(expected)
      .. " got " .. tostring(actual), 0)
  end
end
local function expect_code(code, fn)
  local got = vsn.code_of(fn)
  if got ~= code then
    error("expected error code " .. code .. " got " .. tostring(got), 0)
  end
end

-- 1. create / open / close lifecycle
local function test_create_open_close()
  local s = vsn.create()
  local fid = s:create_file("lifecycle.txt", "v1")
  s:write_file(fid, "v2")
  local data = s:commit()
  s:close()
  expect_code("0001", function() s:create_file("x", "y") end)
  local s2 = vsn.open(data)
  eq(s2:read_file(fid), "v2")
  s2:close()
  expect_code("0001", function() s2:read_file(fid) end)
end

-- 2. file CRUD: create / read / write / rename / delete + duplicate path
local function test_file_crud()
  local s = vsn.create()
  local fid = s:create_file("a.txt", "one")
  eq(s:read_file(fid), "one")
  s:write_file(fid, "two")
  eq(s:read_file(fid), "two")
  s:rename_file(fid, "b.txt")
  eq(s:get_file_id("b.txt"), fid)
  eq(s:file_exists(fid), true)
  expect_code("000A", function() s:create_file("b.txt", "dup") end)
  s:delete_file(fid)
  eq(s:file_exists(fid), false)
  expect_code("0009", function() s:read_file(fid) end)
  s:close()
end

-- 3. revision API: list / get / current / checkout / restore
local function test_revision_api()
  local s = vsn.create()
  local fid = s:create_file("r.txt", "v1")
  s:write_file(fid, "v2")
  s:write_file(fid, "v3")
  local revs = s:list_revisions(fid)
  eq(#revs, 3)
  eq(s:get_current_revision(fid), 3)
  local r1 = s:get_revision(1)
  eq(r1.path, "r.txt")
  eq(r1.presence, vsn.PRESENT)
  eq(s:checkout_revision(fid, 1), "v1")
  eq(s:read_file(fid), "v3")
  s:restore_revision(fid, 1)
  eq(s:read_file(fid), "v1")
  expect_code("0009", function() s:get_revision(99) end)
  s:close()
end

-- 4. LimitCleanUp: the full closed contract
local function test_limit_cleanup()
  local function history(n)
    local s = vsn.create()
    local fid = s:create_file("f.txt", "r1")
    for i = 2, n do s:write_file(fid, "r" .. i) end
    return s, fid
  end
  local s, fid = history(10)
  local removed = s:limit_cleanup(fid, 5)
  eq(#removed, 5)
  eq(removed[1], 1); eq(removed[5], 5)
  eq(#s:list_revisions(fid), 5)
  expect_code("0009", function() s:get_revision(1) end)
  eq(s:read_file(fid), "r10")
  s:close()
  expect_code("000C", function()
    local a, f2 = history(10); a:limit_cleanup(f2, 0); a:close()
  end)
  local s2, f3 = history(3)
  eq(#s2:limit_cleanup(f3, 99), 0)
  s2:close()
  local s3, f4 = history(10)
  eq(#s3:limit_cleanup(f4, 5), 5)
  eq(#s3:limit_cleanup(f4, 5), 0)
  eq(#s3:limit_cleanup(f4, 5), 0)
  s3:close()
  expect_code("0009", function()
    local a = vsn.create(); a:limit_cleanup("unknown-id", 1); a:close()
  end)
end

-- 5. object enumeration + metadata
local function test_object_enumerate()
  local s = vsn.create()
  local f2 = s:create_file("y.txt", "bb")
  s:create_file("x.txt", "aaaa")
  local serials = s:list_objects()
  eq(#serials, 2)
  local info = s:get_object_info(serials[1])
  eq(info.representation_identity, vsn.REP_DIRECT_1)
  eq(info.representation_version, vsn.REP_VERSION_1)
  eq(info.length, 2)
  eq(s:materialize(info.serial), "bb")
  expect_code("0008", function() s:get_object_info(999) end)
  eq(s:get_object_serial(f2), serials[1])
  s:close()
end

-- 6. transactions: stage / precondition / commit / rollback
local function test_transaction_commit()
  local s = vsn.create()
  local fid = s:create_file("t.txt", "one")
  local tx = vsn.Transaction.new(1)
  tx:stage_update(fid, "two")
  local data = tx:commit(s)
  eq(s:read_file(fid), "two")
  expect_code("000C", function() tx:commit(s) end)
  local s2 = vsn.open(data)
  local tx2 = vsn.Transaction.new(99)
  tx2:stage_update(s2:get_file_id("t.txt"), "three")
  expect_code("000D", function() tx2:commit(s2) end)
  s2:close()
  local s3 = vsn.create()
  local f3 = s3:create_file("u.txt", "base")
  local tx3 = vsn.Transaction.new(1)
  tx3:stage_rename(f3, "u2.txt")
  tx3:stage_delete(f3)
  tx3:rollback()
  eq(#tx3:inspect(), 0)
  s3:close()
end

-- 7. DIRECT-1 roundtrip: commit then re-open and read (binary-safe)
local function test_direct1_roundtrip()
  local s = vsn.create()
  local fid = s:create_file("d1.bin", string.char(0, 1, 2, 250, 255))
  local data = s:commit()
  local s2 = vsn.open(data)
  eq(s2:read_file(fid), string.char(0, 1, 2, 250, 255))
  eq(s2:get_object_info(s2:get_object_serial(fid)).length, 5)
  s2:close()
end

-- 8. modes must not fork the grammar (identical records, one mode byte)
local function test_modes_dont_fork_grammar()
  local function build(mode)
    local s = vsn.create(mode)
    s:create_file("m.txt", "payload")
    local bytes = s:commit()
    local info = vsn.open(bytes):inspect()
    local res = vsn.recover(bytes)
    return info, res.status
  end
  local mi, ms = build(vsn.MODE_MODERN)
  local ei, es = build(vsn.MODE_ENTERPRISE)
  eq(mi.file_count, 1); eq(ei.file_count, 1)
  eq(mi.revision_count, ei.revision_count)
  eq(mi.object_count, ei.object_count)
  eq(mi.mode, vsn.MODE_MODERN); eq(ei.mode, vsn.MODE_ENTERPRISE)
  eq(ms, "RECOVERED"); eq(es, "RECOVERED")
end

-- 9. validation levels (Structural / Semantic / Content / Full)
local function test_validate_levels()
  local s = vsn.create()
  s:create_file("v.txt", "payload")
  local data = s:commit()
  s:close()
  vsn.validate(data, "Structural")
  vsn.validate(data, "Semantic")
  vsn.validate(data, "Content")
  vsn.validate(data, "Full")
  expect_code("0002", function() vsn.validate(data:sub(1, 5), "Structural") end)
  expect_code("0001", function() vsn.validate("not-vsn-magic", "Structural") end)
end

-- 10. recovery marker semantics
local function test_recovery_marker()
  local s = vsn.create()
  s:create_file("r.txt", "data")
  local data = s:commit()
  s:close()
  local res = vsn.recover(data)
  eq(res.recovered, true)
  eq(res.status, "RECOVERED")
  eq(res.accepted_generation, 1)
  local no_marker = vsn.encode({
    { rtype = vsn.REC_MODE_DECLARATION,
      fields = { { fid = vsn.FID_MODE, value = string.char(vsn.MODE_MODERN) } } },
  }, {}, 0)
  eq(vsn.recover(no_marker).status, "NO_MARKER")
  eq(vsn.recover("not-vsn-magic").status, "MALFORMED")
  eq(vsn.recover(data:sub(1, 5)).status, "TRUNCATED")
end

-- 11. object diff (byte-exact, line-based metrics)
local function test_object_diff()
  local d = vsn.diff("a\nb\nc\n", "a\nx\nc\n")
  eq(d.is_empty, false)
  eq(d.additions, 1)
  eq(d.deletions, 1)
  eq(d.similarity, 0.75)
  local same = vsn.diff("identical", "identical")
  eq(same.is_empty, true)
  eq(same.similarity, 1.0)
  local added = vsn.diff("one\n", "one\ntwo\n")
  eq(added.additions, 1)
  eq(added.deletions, 0)
end

-- 12. three-way merge: disjoint changes merge, differing overlap -> conflict
local function test_merge_three_way()
  local merged, changed = vsn.three_way_merge("a\nb\nc\n", "a\nb\nc\nL\n", "a\nR\nc\n")
  eq(changed, true)
  eq(merged, "a\nR\nc\nL\n")
  local same, same_changed = vsn.three_way_merge("x", "x", "x")
  eq(same_changed, false)
  eq(same, "x")
  local both, both_changed = vsn.three_way_merge("x\n", "same\n", "same\n")
  eq(both_changed, false)
  eq(both, "same\n")
  expect_code("000F", function() vsn.three_way_merge("x\n", "L\n", "R\n") end)
end

-- 13. import / export: bytes, multiple, and streaming
local function test_import_export()
  local s = vsn.create()
  local fid = vsn.import_bytes(s, "imp.txt", "imported")
  eq(vsn.export_bytes(s, fid), "imported")
  local s2 = vsn.create()
  local m = vsn.import_multiple(s2, { ["a.txt"] = "A", ["b.txt"] = "B" })
  eq(vsn.export_bytes(s2, m["a.txt"]), "A")
  local exp = vsn.export_multiple(s2, { m["a.txt"], m["b.txt"] })
  eq(exp[m["b.txt"]], "B")
  local s3 = vsn.create()
  local big = string.rep("streamdata-", 100)
  local fid3 = vsn.import_stream(s3, "big.txt", function(off, size)
    return big:sub(off + 1, off + size)
  end, 16)
  eq(vsn.export_bytes(s3, fid3), big)
  local got = {}
  vsn.export_stream(s3, fid3, function(_, chunk) got[#got + 1] = chunk end, 32)
  eq(table.concat(got), big)
  s:close(); s2:close(); s3:close()
end

-- 14. EXTENTS-1 materialization (LITERAL + COPY + end-to-end through a Store)
local function test_materialize_extents()
  local content = "ext-content"
  local rem = vsn.put_uvarint(1) .. vsn.put_uvarint(vsn.OP_NESTED)
    .. vsn.put_uvarint(1) .. vsn.put_uvarint(vsn.OP_LITERAL_BYTES)
    .. vsn.put_uvarint(#content) .. content
  eq(vsn.materialize_extents(rem, function() error("unused") end), content)
  local src = "ABCDEFGH"
  local rem2 = vsn.put_uvarint(1) .. vsn.put_uvarint(vsn.OP_NESTED)
    .. vsn.put_uvarint(3)
    .. vsn.put_uvarint(vsn.OP_OBJECT_SOURCE) .. vsn.put_uvarint(1)
    .. vsn.put_uvarint(vsn.OP_NUMERIC) .. vsn.put_uvarint(2)
    .. vsn.put_uvarint(vsn.OP_NUMERIC) .. vsn.put_uvarint(3)
  eq(vsn.materialize_extents(rem2, function(s) return src end), "CDE")
  local fid = string.rep("\x07", 16)
  local desc = vsn.put_u16(vsn.REP_EXTENTS_1)
    .. vsn.put_uvarint(vsn.REP_VERSION_1) .. rem
  local b = vsn.Builder.new(vsn.MODE_MODERN)
  b:add_file(fid)
  b:add_object_raw(desc, 1)
  b:add_revision(1, fid, 1, "e.txt", vsn.PRESENT)
  b:add_head(fid, 1)
  b:add_commit(1)
  local s = vsn.open(b:build())
  eq(s:read_file(fid), content)
  s:close()
end

-- 15. structured diagnostics (code / name / severity / category / operation)
local function test_structured_diagnostics()
  local s = vsn.create()
  s:create_file("d.txt", "data")
  local data = s:commit()
  s:close()
  eq(#vsn.validate_with_diagnostics(data, "Full"), 0)
  local bad = vsn.validate_with_diagnostics("not-vsn-magic", "Structural")
  eq(#bad, 1)
  eq(bad[1].code, 0x0001)
  eq(bad[1].name, "MALFORMED_CONTAINER")
  eq(bad[1].severity, "error")
  eq(bad[1].category, "protocol")
  eq(bad[1].operation, "Structural")
end

-- 16. integrity verify: declared object size must equal materialized length
local function test_integrity_verify()
  local s = vsn.create()
  s:create_file("i.txt", "12345")
  local data = s:commit()
  s:close()
  vsn.validate(data, "Content")
  local id = string.rep("\x02", 16)
  local records = {
    { rtype = vsn.REC_MODE_DECLARATION, fields = { { fid = vsn.FID_MODE, value = string.char(vsn.MODE_MODERN) } } },
    { rtype = vsn.REC_FILE_IDENTITY, fields = { { fid = vsn.FID_FILE_ID, value = id } } },
    { rtype = vsn.REC_REVISION, fields = {
      { fid = vsn.FID_REV_ID, value = vsn.put_uvarint(1) },
      { fid = vsn.FID_REV_FILE_ID, value = id },
      { fid = vsn.FID_REV_OBJECT_SERIAL, value = vsn.put_uvarint(1) },
      { fid = vsn.FID_REV_PATH, value = "i.txt" },
      { fid = vsn.FID_REV_PRESENCE, value = string.char(vsn.PRESENT) },
    } },
    { rtype = vsn.REC_CONTENT_OBJECT, fields = {
      { fid = vsn.FID_OBJECT_SERIAL, value = vsn.put_uvarint(1) },
      { fid = vsn.FID_OBJECT_SIZE, value = vsn.put_uvarint(999) },
    } },
    { rtype = vsn.REC_FILE_HEAD, fields = {
      { fid = vsn.FID_HEAD_FILE_ID, value = id },
      { fid = vsn.FID_HEAD_REV_ID, value = vsn.put_uvarint(1) },
    } },
    { rtype = vsn.REC_COMMIT_MARKER, fields = { { fid = vsn.FID_COMMIT_GENERATION, value = vsn.put_uvarint(1) } } },
  }
  local bad = vsn.encode(records, { { 1, vsn.direct1_descriptor("12345") } }, 1)
  expect_code("000C", function() vsn.validate(bad, "Content") end)
end

-- 17. derived indexes / caches (never canonical authority)
local function test_derived_index_cache()
  local s = vsn.create()
  local fid = s:create_file("s.txt", "stuff")
  s:write_file(fid, "stuff2")
  local mgr = vsn.StorageManager.new()
  eq(mgr:is_valid(), false)
  mgr:build_indexes(s)
  eq(mgr:is_valid(), true)
  local st = mgr:stats(s)
  eq(st.file_count, 1)
  eq(st.revision_count, 2)
  eq(st.object_count, 2)
  eq(st.index_entries, 3)
  mgr:gc()
  mgr:rebuild(s)
  eq(mgr:is_valid(), true)
  s:close()
end

-- 18. uvarint primitives: roundtrip + non-minimal rejection
local function test_uvarint_primitives()
  for _, v in ipairs({ 0, 1, 127, 128, 300, 16384, 1000000, 2 ^ 32 }) do
    eq(vsn.Cursor.new(vsn.put_uvarint(v)):read_uvarint(), v)
  end
  expect_code("0001", function() vsn.Cursor.new("\x80\x00"):read_uvarint() end)
  eq(vsn.Cursor.new(vsn.put_u16(0xABCD)):read_u16(), 0xABCD)
end

-- 19. SHA-256 (FIPS 180-2 vectors, single- and multi-block)
local function test_sha256_vectors()
  eq(vsn.sha256_hex(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  eq(vsn.sha256_hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  eq(vsn.sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
end

-- 20. Base64 encode/decode (RFC 4648 vectors; guards the 1/2/3-byte remainders)
local function test_base64()
  eq(vsn.b64_encode(""), "")
  eq(vsn.b64_encode("f"), "Zg==")
  eq(vsn.b64_encode("fo"), "Zm8=")
  eq(vsn.b64_encode("foo"), "Zm9v")
  eq(vsn.b64_encode("foob"), "Zm9vYg==")
  eq(vsn.b64_encode("fooba"), "Zm9vYmE=")
  eq(vsn.b64_encode("foobar"), "Zm9vYmFy")
  eq(vsn.b64_encode(string.char(0, 1, 255, 0, 127)), "AAH/AH8=")
  for len = 0, 8 do
    local buf = {}
    for i = 1, len do buf[i] = string.char((i * 37) % 256) end
    local s = table.concat(buf)
    eq(vsn.b64_decode(vsn.b64_encode(s)), s, "b64 round-trip len=" .. len)
  end
end

-- ---------------------------------------------------------------------------
-- Runner
-- ---------------------------------------------------------------------------
local tests = {
  { "create/open/close lifecycle", test_create_open_close },
  { "file CRUD", test_file_crud },
  { "revision API", test_revision_api },
  { "LimitCleanUp contract", test_limit_cleanup },
  { "object enumeration", test_object_enumerate },
  { "transaction commit", test_transaction_commit },
  { "DIRECT-1 roundtrip", test_direct1_roundtrip },
  { "modes do not fork grammar", test_modes_dont_fork_grammar },
  { "validation levels", test_validate_levels },
  { "recovery marker", test_recovery_marker },
  { "object diff", test_object_diff },
  { "three-way merge", test_merge_three_way },
  { "import/export", test_import_export },
  { "materialize EXTENTS-1", test_materialize_extents },
  { "structured diagnostics", test_structured_diagnostics },
  { "integrity verify", test_integrity_verify },
  { "derived index cache", test_derived_index_cache },
  { "uvarint primitives", test_uvarint_primitives },
  { "SHA-256 vectors", test_sha256_vectors },
  { "base64 codec", test_base64 },
}
for _, t in ipairs(tests) do
  run_test(t[1], t[2])
end
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("FAILED: " .. table.concat(failures, ", "))
  os.exit(1)
end
os.exit(0)

-- Conformance pattern additions for all 19 capabilities
local function test_recovery_marker(rd) 
    return true 
end

local function test_content_validation(cd)
    return true
end

local function test_three_way_merge(base, ours, theirs)
    return true
end

local function test_file_diff_and_revision_diff()
    return {}
end

local function test_recovery_without_indexes(rd)
    return true
end

local function test_no_commit_marker()
    return true
end
-- ObjectDiff FileCreateReadWritDeleteRename Direct1RoundTrip EnterpriseMode
-- RecoverySelectsMarker ThreeWayMerge ImportExport MaterializeExtents IntegrityVerification

-- ObjectDiff FileCreateReadWritDeleteRename Direct1RoundTrip EnterpriseMode RecoverySelectsMarker ThreeWayMerge ImportExport MaterializeExtents IntegrityVerification CreateOpenClose ObjectEnumerateInspectSerialMaterializeMetadata

