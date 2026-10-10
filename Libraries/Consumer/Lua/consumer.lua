-- Independent Lua consumer: loads vsn.lua and uses ONLY the public API.
-- Verifies Storage Policy public API + wire-out (to_bytes) + wire-in (open) round-trip.
local script = arg[0]:gsub("\\", "/")
local cdir = script:match("^(.*)/consumer%.lua$")
assert(cdir, "run as: lua <abs>/Libraries/Consumer/Lua/consumer.lua")
package.path = cdir .. "/../../Lua/?.lua;" .. package.path
local vsn = require "vsn"

local fails = 0
local function check(c, m)
  if c then print("ok  - " .. m) else print("FAIL: " .. m) fails = fails + 1 end
end

-- 1. Four canonical policy values (1..4) publicly defined.
check(vsn.STORAGE_HIGHLY_VERTICAL == 1, "SP 1 = HIGHLY_VERTICAL")
check(vsn.STORAGE_VERTICAL == 2, "SP 2 = VERTICAL")
check(vsn.STORAGE_HORIZONTAL == 3, "SP 3 = HORIZONTAL")
check(vsn.STORAGE_HIGHLY_HORIZONTAL == 4, "SP 4 = HIGHLY_HORIZONTAL")

-- 2. create-with-policy is publicly accessible and stores the canonical value.
local s4 = vsn.create_with_storage_policy(4)
check(type(s4) == "table", "create_with_storage_policy returns a store")
check(s4.storage_policy == 4, "store.storage_policy == 4 (HIGHLY_HORIZONTAL)")

-- 3. Wire-out (to_bytes) + wire-in (open) round-trips the canonical value for all four.
local all_ok, bytes4 = true, nil
do
  local ok, b = pcall(function() return s4:to_bytes() end)
  check(ok and type(b) == "string" and #b > 0, "to_bytes produced canonical bytes")
  if ok then
    bytes4 = b
    check(vsn.open(b).storage_policy == 4, "open(bytes).storage_policy == 4 (round-trip)")
  end
end
for _, p in ipairs({ 1, 2, 3, 4 }) do
  local ss = vsn.create_with_storage_policy(p)
  local ok, b = pcall(function() return ss:to_bytes() end)
  if not ok or vsn.open(b).storage_policy ~= p then all_ok = false end
end
check(all_ok, "SP round-trips 1..4 via to_bytes/open")

-- 4. Distinct policies -> distinct wire bytes.
local _, b3 = pcall(function() return vsn.create_with_storage_policy(3):to_bytes() end)
check(type(bytes4) == "string" and type(b3) == "string" and bytes4 ~= b3, "distinct policies -> distinct wire bytes")

-- 5. Validation + recovery accept canonical bytes.
if bytes4 then
  check(vsn.validate_ok(bytes4, "Full") == true, "validate_ok(Full) clean")
  local ok, rec = pcall(function() return vsn.recover(bytes4) end)
  check(ok and type(rec) == "table" and rec.status ~= nil, "recover returns a result")
end

-- 6. Malformed / out-of-range: the public API is permissive (raw int); canonical set is 1..4.
local b0_ok, b0 = pcall(function() return vsn.create_with_storage_policy(0):to_bytes() end)
local note = b0_ok and (vsn.open(b0).storage_policy == 0) or false
print(("note: out-of-range 0 round-trips as %s (parser permissive; canonical SP set is 1..4)"):format(tostring(vsn.open(b0).storage_policy)))
check(b0_ok, "out-of-range value does not crash the writer (documented permissive behavior)")

if fails == 0 then print("CONSUMER LUA PASS")
else print("CONSUMER LUA FAIL (" .. fails .. ")") end
os.exit(fails == 0 and 0 or 1)
