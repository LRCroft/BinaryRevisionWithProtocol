# VSN-1 independent consumer (Nim) -- Storage Policy round-trip.
# Uses the library's encodeWithSP (wire-out) + importBytes (wire-in).
import vsn, strutils

proc hasSig(b: string): bool =
  let sig = char(0) & char(9) & char(4) & char(9) & char(1) & char(1)
  contains(b, sig)

var bad = false
for p in 1..4:
  let b = encodeWithSP(1, 0, p)
  if not hasSig(b):
    echo "FAIL p=" & $p & " wire-out"
    bad = true
  var s = createWithStoragePolicy(1)
  s.importBytes(b)
  let got = exportStoragePolicy(s)
  if got != p:
    echo "FAIL p=" & $p & " got=" & $got
    bad = true

if bad:
  echo "CONSUMER NIM FAIL"
  quit(1)
else:
  echo "CONSUMER NIM PASS"
