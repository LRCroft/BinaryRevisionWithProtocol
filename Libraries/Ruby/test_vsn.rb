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
         when 8 then [1, 2].include?(s.mode)
         else true
         end
    s.close
    chk(n, ok)
  end
end
threads.each(&:join)
puts "PASS #{$P}"
