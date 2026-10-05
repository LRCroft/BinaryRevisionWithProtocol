# VSN-1 parallel conformance test -- full 19 caps
import vsn, algorithm, strutils

var passed = 0

proc runCap(n: int): bool =
  let s = create(MODE_MODERN)
  var ok = false
  case n
  of 1: ok = getMode(s) == MODE_MODERN
  of 2:
    try:
      let fid = createFile(s, "a", "hello")
      ok = fid.len > 0
    except: ok = false
  of 3:
    try:
      var s2 = s; let (f,s3) = createFile(s2, "r", "v1")
      _ = writeFile(s3, f, "v2"); let (_ ,s4) = writeFile(s3, f, "v3")
      ok = listRevisions(s4, f).len >= 3
    except: ok = false
  of 4:
    try:
      var s2 = s; let (f,s3) = createFile(s2, "lc", "x")
      for i in 1..5: discard writeFile(s3, f, $i); result = s3
      let (dropped,_) = limitCleanup(result, f, 3); ok = dropped.len == 2
    except: ok = false
  of 5:
    try: var s2=s; discard createFile(s2, "o", "AB"); ok = listObjects(s2).len >= 1
    except: ok = false
  of 6:
    try: let tx = beginTransaction(s); let _ = stageAdd(tx, "t", "x")
         let (out_bytes,_) = commit(s, tx); ok = out_bytes.len >= 8
    except: ok = false
  of 7: ok = REP_DIRECT_1 == 1 and REP_EXTENTS_1 == 2
  of 8: ok = getMode(s) in [MODE_MODERN, MODE_ENTERPRISE]
  of 9: ok = validateStructural(s)
  of 10: ok = recover(exportBytes(s)) >= 0
  of 11:
    try: let s2=create(MODE_MODERN); discard createFile(s, "x", "1")
         let d=diffStores(s,s2); ok = d.added.len > 0
    except: ok = false
  of 12:
    try:
      let base=create(MODE_MODERN), ours=create(MODE_MODERN), theirs=create(MODE_MODERN)
      let m=mergeThreeWay(base,ours,theirs); ok = not isNil(m)
    except: ok = false
  of 13:
    try: let bytes=exportBytes(s); s2=open(bytes); ok = getMode(s2)==MODE_MODERN
    except: ok = false
  of 14:
    try: let fid=createFile(s, "big", "bd"); let c=readFile(s, fid); ok = c.len == 2
    except: ok = false
  of 15:
    try: let d=diagnostics(s, "Full"); ok = high(d) >= low(d)
    except: ok = false
  of 16: ok = integrityVerify(exportBytes(s))
  of 17:
    try: let _=createFile(s, "stat", "x"); let st=getStats(s); ok = st.files >= 1
    except: ok = false
  of 18:
    let b=newBuilder(MODE_ENTERPRISE); ok = getMode(b) == MODE_ENTERPRISE
  of 19: ok = checkMagicBytes(encode(1,1))
  else: ok = false
  closeStore(s)
  result = ok

proc main() =
  for i in 1..19:
    if runCap(i): passed += 1; echo "PASS ", i
    else: echo "FAIL ", i
  echo "PASS ", passed

main()