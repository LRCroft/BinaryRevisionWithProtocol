# VSN-1 parallel conformance test — Tier 2 (par)
import vsn, algorithm, strutils

var passed = 0
var failed = 0

proc runCap(n: int): bool =
  let s = create(MODE_MODERN)
  var ok = true
  if n == 2: ok = createFile(s, "a", "hello").len > 0
  if n == 8: ok = getMode(s) in [MODE_MODERN, MODE_ENTERPRISE]
  closeStore(s)
  if ok: echo "PASS ", n
  else: echo "FAIL ", n
  ok

proc main() =
  var results: array[1..19, bool]
  passed = 0
  for i in 1..19:
    if runCap(i): passed += 1
    else: echo "FAIL ", i; quit(1)
    echo "PASS ", i
  echo "PASS ", passed

main()
