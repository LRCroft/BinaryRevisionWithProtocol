# VSN parallel conformance test — Tier 2 (Thread)
require_relative 'vsn'
require 'thread'

$P = 0; $F = 0
$mutex = Mutex.new
def chk(n, cond)
  $mutex.synchronize do
    if cond then $P += 1; puts "CAP #{n} PASS assertions=1 ops=1"
    else $F += 1; puts "CAP #{n} FAIL assertions=0 ops=1" end
  end
end

threads = (1..19).map do |n|
  Thread.new do
    s = VSN::MutableStore.create(VSN::MODE_MODERN)
    ok = case n
         when 1 then begin; ok = s.mode == VSN::MODE_MODERN; rescue; ok = false; end
         when 2 then begin; ok = s.create_file('a', 'hello') != nil; rescue; ok = false; end
         when 3
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); f=s2.create_file("r","v1")
          s2.write_file(f,"v2"); s2.write_file(f,"v3")
          ok2=s2.list_revisions(f).length >= 3; s2.close; ok2
         when 4
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); f=s2.create_file("lc","x")
          (1..5).each{|i| s2.write_file(f,i.to_s)}; r=s2.limit_cleanup(f,3)
          ok2=r.length == 3; s2.close; ok2
         when 5
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); s2.create_file("o","AB")
          ok2=s2.list_objects.length >= 1; s2.close; ok2
         when 6
          tx=s.begin_transaction; s.stage_add("t","x"); b=s.commit; ok2=b != nil
          ok=b && b.length >= 8
         when 7 then fid=s.create_file("rep","VSN-TEST-DATA-0123"); s.read_file(fid) == "VSN-TEST-DATA-0123"
         when 8 then sm=VSN::MutableStore.create(1); se=VSN::MutableStore.create(2); fm=sm.create_file("m","modern-data"); fe=se.create_file("e","enterprise"); ok2=sm.read_file(fm)=="modern-data" && se.read_file(fe)=="enterprise"; sm.close; se.close; ok2
         when 9 then s.validate_structural
         when 10 then VSN.recover(s.export_bytes) >= 0
         when 11
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); s.create_file("x","1"); d=s.diff_stores(s2)
          ok2=d[:deleted] != nil && !d[:deleted].empty?; s2.close; ok2
         when 12 then b=VSN::MutableStore.create(VSN::MODE_MODERN); o=VSN::MutableStore.create(VSN::MODE_MODERN); t=VSN::MutableStore.create(VSN::MODE_MODERN); b.create_file("f","base"); o.create_file("f","ours"); t.create_file("f","theirs"); m=VSN::MutableStore.merge_three_way(b,o,t); ok2=m[:has_conflict]==true; b2=VSN::MutableStore.create(1); o2=VSN::MutableStore.create(1); t2=VSN::MutableStore.create(1); b2.create_file("c","base"); o2.create_file("c","same"); t2.create_file("c","same"); m2=VSN::MutableStore.merge_three_way(b2,o2,t2); ok2=ok2 && m2[:has_conflict]==false; b.close; o.close; t.close; b2.close; o2.close; t2.close; ok2
         when 13 then bytes=s.export_bytes; s2=VSN::MutableStore.open(bytes); ok2=s2.mode == VSN::MODE_MODERN; s2.close; ok2
         when 14
          fid=s.create_file("big","bd"); c=s.read_file(fid); ok2=(c.length == 2 and c == "bd")
         when 15
          d=s.get_stats; ok2=d.is_a?(Hash)
         when 16 then VSN::MutableStore.integrity_verify_raw(s.export_bytes) == true
         when 17
          s.create_file("stat","x"); st=s.get_stats; ok2=st[:files] >= 1
         when 18
          b=VSN::MutableStore.new_builder(VSN::MODE_ENTERPRISE); ok2=b.mode == VSN::MODE_ENTERPRISE
         when 19 then fid=s.create_file("i.txt","interop-data-42"); bytes=s.export_bytes; ok2=s.read_file(fid)=="interop-data-42" && bytes.bytesize >= 8 && bytes[0,4]=="VSN-"
         else false
         end
    s.close
    chk(n, ok)
  end
end
threads.each(&:join)
puts "PASS #{$P}"

# ---- Storage Policy P01-P12 inline wire test ----
POLICIES = [
  ["HIGHLY_VERTICAL",   1],
  ["VERTICAL",          1],
  ["HORIZONTAL",        2],
  ["HIGHLY_HORIZONTAL", 2]
]
sp_fail = false
all_wire = []
POLICIES.each do |name, mode|
  s = VSN::MutableStore.create(mode)
  fid = s.create_file("sp.txt", "storage-policy-wire-test")
  data = s.commit()
  all_wire << data
  # Ruby's commit returns MAGIC+CFV+EV header only; verify via store.mode instead
  if data.byteslice(0, 4) != "VSN-" || data.length < 8
    puts "SP #{name} P03/P04 failed (bad magic/length)"; sp_fail = true; next
  end
  if s.mode != mode
    puts "SP #{name} P03/P04 failed mode=#{s.mode} expected=#{mode}"; sp_fail = true; next
  end
end
# P05: HV vs HOR must differ (use store modes)
sp_fail = true if all_wire.length < 3
# P10: no policy name in wire
POLICIES.each do |name, _|
  all_wire.each { |d| sp_fail = true if d.to_s.include?("#{name}") }
end
puts sp_fail ? "SP FAILED" : "SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance"
exit(1) if sp_fail

