# VSN-1 parallel conformance test — Tier 2 (Thread)
require_relative 'vsn'
require 'thread'

$P = 0; $F = 0
$mutex = Mutex.new
def chk(n, cond)
  $mutex.synchronize do
    if cond then $P += 1; puts "PASS #{n}"
    else $F += 1; puts "FAIL #{n}" end
  end
end

threads = (1..19).map do |n|
  Thread.new do
    s = VSN::MutableStore.create(VSN::MODE_MODERN)
    ok = case n
         when 1 then s.mode == VSN::MODE_MODERN
         when 2 then s.create_file('a', 'hello') != nil
         when 3
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); f=s2.create_file("r","v1")
          s2.write_file(f,"v2"); s2.write_file(f,"v3")
          ok2=s2.list_revisions(f).length >= 3; s2.close; ok2
         when 4
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); f=s2.create_file("lc","x")
          (1..5).each{|i| s2.write_file(f,i.to_s)}; r=s2.limit_cleanup(f,3)
          ok2=r.length == 2; s2.close; ok2
         when 5
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); s2.create_file("o","AB")
          ok2=s2.list_objects.length >= 1; s2.close; ok2
         when 6
          tx=s.begin_transaction; s.stage_add(tx,"t","x"); (b,_)=s.commit(tx)
          ok=b && b.length >= 8
         when 7 then VSN::REP_DIRECT_1 == 1 && VSN::REP_EXTENTS_1 == 2
         when 8 then [1, 2].include?(s.mode)
         when 9 then s.validate_structural
         when 10 then VSN.recover(s.export_bytes) >= 0
         when 11
          s2=VSN::MutableStore.create(VSN::MODE_MODERN); s.create_file("x","1"); d=s.diff_stores(s2)
          ok2=d[:added] != nil && !d[:added].empty?; s2.close; ok2
         when 12
          b=VSN::MutableStore.create(VSN::MODE_MODERN); o=VSN::MutableStore.create(VSN::MODE_MODERN); t=VSN::MutableStore.create(VSN::MODE_MODERN)
          m=VSN::merge_three_way(b,o,t); ok2=m != nil; b.close; o.close; t.close
         when 13
          bytes=s.export_bytes; s2=VSN::MutableStore.open(bytes); ok2=s2.mode == VSN::MODE_MODERN; s2.close
         when 14
          fid=s.create_file("big","bd"); c=s.read_file(fid); ok2=c.length >= 0
         when 15
          d=s.diagnostics("Full"); ok2=d.is_a?(Array)
         when 16 then VSN.integrity_verify(s.export_bytes) == true
         when 17
          s.create_file("stat","x"); st=s.get_stats; ok2=st[:files] >= 1
         when 18
          b=VSN::new_builder(VSN::MODE_ENTERPRISE); ok2=b.mode == VSN::MODE_ENTERPRISE
         when 19 then VSN.check_magic_bytes(VSN.encode(1,1))
         else false
         end
    s.close
    chk(n, ok)
  end
end
threads.each(&:join)
puts "PASS #{$P}"
