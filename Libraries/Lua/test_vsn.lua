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
    local tx = s
    s:create_file("t", "x")
    local out = vsn.encode({}, {}, 0); ok = #out >= 8
  elseif n == 7 then ok = vsn.REP_DIRECT_1 == 1 and vsn.REP_EXTENTS_1 == 2
  elseif n == 8 then ok = s.mode == 1 or s.mode == 2
  elseif n == 9 then s:create_file("v","x"); ok = vsn.validate_ok(s:commit())
  elseif n == 10 then s:create_file("r","x"); ok = vsn.recover(s:commit()) ~= nil
  elseif n == 11 then
    local s2 = vsn.create(1)
    local d = vsn.diff(s:commit(), s2.data or vsn.encode({}, {}, 0)); ok = type(d) == "table"
  elseif n == 12 then
    local base=s; local ours=vsn.create(1); local theirs=vsn.create(1)
    local m = vsn.three_way_merge(base.data or vsn.encode({}, {}, 0), ours:commit(), theirs:commit()); ok = m ~= nil
  elseif n == 13 then
    local bytes = s:commit(); local s2 = vsn.open(bytes); ok = s2.mode == 1
  elseif n == 14 then
    local fid = s:create_file("big", "bd"); local c = s:read_file(fid); ok = #c == 2
  elseif n == 15 then
    local d = vsn.validate_with_diagnostics(s:commit(), "Full"); ok = type(d) == "table"
  elseif n == 16 then
    local bytes = s:commit(); ok = vsn.validate_ok(bytes)
  elseif n == 17 then
    s:create_file("stat", "x"); ok = vsn.validate_ok(s:commit())
  elseif n == 18 then
    local b = vsn.create(2); ok = b.mode == 2
  elseif n == 19 then ok = vsn.encode({}, {}, 0):sub(1,4) == "VSN-"
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
