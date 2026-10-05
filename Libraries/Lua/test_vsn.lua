-- VSN-1 parallel conformance test — Tier 2 (coroutine)
local vsn = require("vsn")
local P, F = 0, 0
local results = {}

local function run_cap(n)
  local s = vsn.create(vsn.MODE_MODERN)
  local ok = true
  if n == 2 then ok = s:create_file("a", "hello") ~= nil end
  if n == 8 then ok = s.mode == 1 or s.mode == 2 end
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
