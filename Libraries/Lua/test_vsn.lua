-- VSN-1 parallel conformance test — Tier 2 (coroutine)
local vsn = require("vsn")
local P, F = 0, 0
local results = {}

local function run_cap(n)
  local s = vsn.create(vsn.MODE_MODERN)
  local ok = false
  if n == 1 then ok = s.mode == vsn.MODE_MODERN
  elseif n == 2 then ok = s:create_file("a", "hello") ~= nil
  elseif n == 3 then
    local fid = s:create_file("r", "v1")
    s:write_file(fid, "v2"); s:write_file(fid, "v3")
    ok = #s:list_revisions(fid) >= 3
  elseif n == 4 then
    local fid = s:create_file("lc", "x")
    for i=1,5 do s:write_file(fid, string.char(i)) end
    ok = #s:limit_cleanup(fid, 3) == 3
  elseif n == 5 then
    s:create_file("o", "AB"); ok = #s:list_objects() >= 1
  elseif n == 6 then
    local tx = s:begin_transaction()
    s:stage_add(tx, "t", "x")
    local out = s:commit(tx); ok = #out >= 8
  elseif n == 7 then ok = vsn.REP_DIRECT_1 == 1 and vsn.REP_EXTENTS_1 == 2
  elseif n == 8 then ok = s.mode == 1 or s.mode == 2
  elseif n == 9 then ok = s:validate_structural()
  elseif n == 10 then ok = vsn.recover(s:export_bytes()) == 0
  elseif n == 11 then
    local s2 = vsn.create(vsn.MODE_MODERN); s:create_file("x", "1")
    local d = s:diff_stores(s2); ok = next(d.added) ~= nil
  elseif n == 12 then
    local base=s; ours=vsn.create(1); theirs=vsn.create(1)
    local m = s:merge_three_way(ours, theirs); ok = m ~= nil
  elseif n == 13 then
    local bytes = s:export_bytes(); s2 = vsn.open(bytes); ok = s2.mode == 1
  elseif n == 14 then
    local fid = s:create_file("big", "bd"); local c = s:read_file(fid); ok = #c == 2
  elseif n == 15 then
    local d = s:diagnostics("Full"); ok = type(d) == "table"
  elseif n == 16 then
    local bytes = s:export_bytes(); ok = vsn.integrity_verify(bytes) ~= nil
  elseif n == 17 then
    s:create_file("stat", "x"); local st=s:get_stats(); ok = st.files >= 1
  elseif n == 18 then
    local b = vsn.new_builder(2); ok = b.mode == 2
  elseif n == 19 then ok = vsn.check_magic_bytes(vsn.encode(1,1))
  end
  s:close()
  results[n] = ok
  if ok then P = P + 1; print("PASS " .. n)
  else F = F + 1; print("FAIL " .. n) end
end

local co = {}
for i = 1, 19 do co[i] = coroutine.create(function() run_cap(i) end) end
for i = 1, 19 do coroutine.resume(co[i]) end
print("PASS " .. P)
if F > 0 then os.exit(1) end
