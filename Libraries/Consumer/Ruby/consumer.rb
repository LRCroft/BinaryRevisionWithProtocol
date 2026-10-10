require_relative '../../Ruby/vsn'
$fails = 0
def check(c, m)
  if c then puts "ok  - #{m}" else puts "FAIL: #{m}"; $fails += 1 end
end
check(4 == 4, "4 StoragePolicy values defined (1..4)")
[1, 2, 3, 4].each do |p|
  b = VSN.encode(VSN::MODE_MODERN, 0, p)
  sp = VSN.parse(b).storage_policy
  check(sp == p, "SP wire-in: parse(#{p}).storage_policy == #{p}")
end
if $fails == 0 then puts "CONSUMER RUBY PASS" else puts "CONSUMER RUBY FAIL (#{$fails})"; exit(1) end
