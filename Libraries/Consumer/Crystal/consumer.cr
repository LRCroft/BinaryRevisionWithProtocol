require "../../Crystal/vsn.cr"

# VSN independent consumer (Crystal) -- Storage Policy round-trip.
# Uses the library's VSN::StoreWithPolicy + export_bytes (wire-out)
# + VSN::Store.parse_sp (wire-in).
def sig(b)
  n = b.size
  hi = n > 7 ? n - 7 : 0
  (0..hi).each do |i|
    return true if b[i] == 0 && b[i + 1] == 9 && b[i + 2] == 4 &&
                   b[i + 3] == 9 && b[i + 4] == 1 && b[i + 5] == 1
  end
  false
end

bad = false
(1..4).each do |p|
  s = VSN::StoreWithPolicy.create(p)
  b = s.export_bytes
  unless sig(b)
    bad = true
    STDERR.puts "FAIL p=#{p} wire-out"
  end
  got = VSN::Store.parse_sp(b)
  unless got == p
    bad = true
    STDERR.puts "FAIL p=#{p} got=#{got}"
  end
end

puts bad ? "CONSUMER CRYSTAL FAIL" : "CONSUMER CRYSTAL PASS"
exit 1 if bad

