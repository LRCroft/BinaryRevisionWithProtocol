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
  elseif n == 7 then local fid7=s:create_file("rep","VSN-TEST-DATA-0123"); ok = s:read_file(fid7) == "VSN-TEST-DATA-0123"
  elseif n == 8 then local sm8=vsn.create(1); local se8=vsn.create(2); local fm8=sm8:create_file("m","modern"); local fe8=se8:create_file("e","ent"); ok = sm8.mode==1 and se8.mode==2 and sm8:read_file(fm8)=="modern" and se8:read_file(fe8)=="ent"
  elseif n == 9 then s:create_file("v","x"); ok = vsn.validate_ok(s:commit())
  elseif n == 10 then s:create_file("r","x"); ok = vsn.recover(s:commit()) ~= nil
  elseif n == 11 then
    local s2 = vsn.create(1)
    local d = vsn.diff(s:commit(), s2.data or vsn.encode({}, {}, 0)); ok = type(d) == "table"
  elseif n == 12 then
    -- Real 3-way merge (5 cases): identical / ours-only / theirs-only / both-identical / divergent-conflict
    local function m3(b, o, t) local okc, res = pcall(function() return vsn.three_way_merge(b, o, t) end); return okc, res end
    local function norm(x) if type(x) == "string" then return (x:gsub("\n$", "")) end return nil end
    local iok, ire   = m3("A", "A", "A")
    local cok, cre   = m3("A", "B", "A")
    local tok, tre   = m3("A", "A", "B")
    local bidok, bire = m3("A", "B", "B")
    local dfok       = m3("A", "B", "C")
    ok = (iok and norm(ire) == "A") and (cok and norm(cre) == "B") and (tok and norm(tre) == "B")
         and (bidok and norm(bire) == "B") and (not dfok)
  elseif n == 13 then
    local bytes = s:commit(); local s2 = vsn.open(bytes); ok = s2.mode == 1
  elseif n == 14 then
    local fid = s:create_file("big", "bd"); local c = s:read_file(fid); ok = (#c == 2 and c == "bd")
  elseif n == 15 then
    local d = vsn.validate_with_diagnostics(s:commit(), "Full"); ok = type(d) == "table"
  elseif n == 16 then
    local bytes = s:commit(); ok = vsn.validate_ok(bytes)
  elseif n == 17 then
    s:create_file("stat", "x"); ok = vsn.validate_ok(s:commit())
  elseif n == 18 then
    local b = vsn.create(2); ok = b.mode == 2
  elseif n == 19 then local fid19=s:create_file("i","interop-data-42"); local b19=s:commit(); ok = s:read_file(fid19)=="interop-data-42" and b19:sub(1,4)=="VSN-"
  end
  s:close()
  results[n] = ok
  if ok then P = P + 1; print("CAP " .. n .. " PASS assertions=1 ops=1")
  else F = F + 1; print("CAP " .. n .. " FAIL assertions=0 ops=1") end
end

local co = {}
for i = 1, 19 do co[i] = coroutine.create(function() run_cap(i) end) end
for i = 1, 19 do coroutine.resume(co[i]) end
print("PASS " .. P)
if F > 0 then os.exit(1) end
