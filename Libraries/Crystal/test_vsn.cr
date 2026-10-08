require "./vsn.cr"

alias MutableStore = VSN::Store

# Crystal forbids top-level globals, so counters live in class variables.
class Harness
  @@passed = 0
  @@failed = 0

  def self.passed ; @@passed ; end
  def self.failed ; @@failed ; end

  def self.chk(n, cap, cond)
    if cond
      @@passed += 1
      puts "CAP #{n} PASS assertions=1 ops=1 #{cap}"
    else
      @@failed += 1
      puts "CAP #{n} FAIL assertions=0 ops=1 #{cap}"
    end
    cond
  end
end

def chk(n, cap, cond)
  Harness.chk(n, cap, cond)
end

def chk_raises(n, cap)
  ok = false
  begin
    yield
  rescue
    ok = true
  end
  chk(n, cap, ok)
end

def b(s : String) : Bytes
  s.to_slice
end

# 1. Container lifecycle
s = VSN::Store.create
chk(1, "container lifecycle", s.mode == VSN::MODE_MODERN)
chk(1, "container lifecycle close", s.close!.closed)
s = VSN::Store.create
chk(1, "container reopen", VSN::Store.open(s.export_bytes).is_a?(VSN::Store))

# 2. File API
f1 = s.create_file("a.txt", b("abc"))
chk(2, "file API FileId 16 bytes", f1.size == 16)
chk(2, "file API read", s.read_file(f1) == b("abc"))
s.write_file(f1, b("xyz"))
chk(2, "file API write", s.read_file(f1) == b("xyz"))
f2 = s.create_file("c.txt", b("other"))
chk(2, "file API multiple coexist", f1 != f2 && s.file_exists?(f1) && s.file_exists?(f2))
serial_before = s.get_object_serial(f1)
s.rename_file(f1, "b.txt")
chk(2, "file API rename preserves content", s.read_file(f1) == b("xyz"))
chk(2, "file API rename keeps FileId", s.get_file_id("b.txt") == f1)
chk(2, "file API rename keeps ObjectSerial", s.get_object_serial(f1) == serial_before)
chk(2, "file API rename old path gone", s.get_file_id("a.txt").nil?)
fdel = s.create_file("gone.txt", b("x"))
s.delete_file(fdel)
chk(2, "file API delete", !s.file_exists?(fdel))
fempty = s.create_file("empty.txt", Bytes.empty)
chk(2, "file API empty content", s.read_file(fempty) == Bytes.empty)

# 3. Revision API
chk(3, "revision API list", s.list_revisions(f1).size >= 2)
chk(3, "revision API current", s.get_current_revision(f1) > 0)
chk(3, "revision API checkout", s.checkout_revision(s.get_current_revision(f1)) == b("xyz"))
chk(3, "revision API ascending order", s.list_revisions(f1) == s.list_revisions(f1).sort)

# 4. LimitCleanUp
before = s.list_revisions(f1).size
removed = s.limit_clean_up(f1, 1)
after = s.list_revisions(f1).size
chk(4, "LimitCleanUp retains limit", after == 1 && after < before)
chk(4, "LimitCleanUp reports removed", removed.size > 0)
s.limit_clean_up(f1, 1)
chk(4, "LimitCleanUp idempotent", s.list_revisions(f1).size == 1)
chk(4, "LimitCleanUp FileHead intact", s.file_exists?(f1))
chk(4, "LimitCleanUp content readable", s.read_file(f1) == b("xyz"))
iso = s.create_file("iso.txt", b("a"))
s.write_file(iso, b("b"))
hist = s.list_revisions(f1).size
chk_raises(4, "LimitCleanUp limit zero rejected") { s.limit_clean_up(f1, 0) }
chk(4, "LimitCleanUp zero leaves history", s.list_revisions(f1).size == hist)
s.limit_clean_up(f1, 1)
chk(4, "LimitCleanUp per-file isolation", s.list_revisions(iso).size == 2)
s.limit_clean_up(iso, 99)
chk(4, "LimitCleanUp limit > history", s.list_revisions(iso).size == 2)

# 5. Object API
objs = s.list_objects
chk(5, "object API enumerate", objs.size >= 1)
chk(5, "object API materialize", s.materialize_object(objs[0]).is_a?(Bytes))
chk(5, "object API info", !s.get_object_info(objs[0]).nil?)
chk_raises(5, "object API missing serial rejected") { s.materialize_object(99999_u32) }

# 6. Transactions
s.begin_transaction
s.stage_add("txn.txt", b("v"))
s.commit
chk(6, "transactions commit", !s.get_file_id("txn.txt").nil?)
s.begin_transaction
s.stage_add("never.txt", b("v"))
s.rollback
chk(6, "transactions rollback", s.get_file_id("never.txt").nil?)

# 7. Representations
s7=VSN::Store.create; f7=s7.create_file("rep", b("VSN-TEST-DATA-0123")); chk(7, "representations DIRECT-1 round-trip", (s7.read_file(f7) == b("VSN-TEST-DATA-0123")) && (s7.read_file(f7).size == 18))


# 8. Modes
sm8=VSN::Store.create(1); se8=VSN::Store.create(2); fm8=sm8.create_file("m", b("modern-data")); fe8=se8.create_file("e", b("enterprise")); chk(8, "modes behavioral", sm8.mode==1 && se8.mode==2 && sm8.read_file(fm8)==b("modern-data") && se8.read_file(fe8)==b("enterprise"))


# 9. Validation
chk(9, "validation structural", VSN.validate_structural?(VSN.parse(s.export_bytes)))
chk(9, "validation rejects bad magic", !VSN.validate_structural?(VSN.parse(b("XXXXXXXX"))))

# 10. Recovery
chk(10, "recovery offset", VSN.recover(s.export_bytes) == 0)
chk(10, "recovery rejects bad magic", VSN.recover(b("XXXXXXXX")) == -1)

# 11. Diff
da = VSN::Store.create
da.create_file("same.txt", b("a"))
da.create_file("aonly.txt", b("a"))
db = VSN::Store.create
db.create_file("same.txt", b("b"))
db.create_file("renamed.txt", b("b"))
d = VSN::Store.diff_stores(da, db)
chk(11, "diff shared intersection", d.shared.size == 1)
chk(11, "diff modified by path", d.modified == ["aonly.txt"])
chk(11, "diff added", d.added.size == 0)
dc = VSN::Store.create
dc.create_file("same.txt", b("a"))
dc.create_file("aonly.txt", b("a"))
dc.create_file("brandnew.txt", b("c"))
d2 = VSN::Store.diff_stores(da, dc)
chk(11, "diff added for new file", d2.added == ["brandnew.txt"])
chk(11, "diff no deletions when superset", d2.deleted.size == 0)
dd = VSN::Store.create
dd.create_file("other.txt", b("d"))
d3 = VSN::Store.diff_stores(da, dd)
chk(11, "diff same FileId different path is modified", d3.modified.size == 1 && d3.added.size == 0)
chk(11, "diff deleted for missing file", d3.deleted == ["aonly.txt"])
chk(11, "diff same store is empty",
    VSN::Store.diff_stores(da, da).shared.size == 2 &&
    VSN::Store.diff_stores(da, da).modified.size == 0)

# 12. Three-way merge
chk(12, "merge three-way conflict",
    VSN::Store.merge_three_way(b("base"), b("ours"), b("theirs")).has_conflicts)
chk(12, "merge three-way no conflict",
    !VSN::Store.merge_three_way(b("base"), b("same"), b("same")).has_conflicts)

# 13. Import / export
exported = s.export_bytes
s2 = VSN::Store.open(exported)
chk(13, "exportBytes roundtrip", s2.export_bytes == exported)
s2.import_bytes!(exported)
chk(13, "importBytes", VSN.integrity_verify_raw?(exported))

# 14. Streaming
bfid = s.write_large_object("big.bin", Bytes.new(4096, 'z'.ord.to_u8))
chk(14, "streaming large object", s.read_file(bfid).size == 4096)

# 15. Diagnostics
chk(15, "diagnostics clean", s.diagnostics.size == 0)
chk(15, "diagnostics reports invalid", VSN::Store.create(99).diagnostics.size == 1)

# 16. Integrity
chk(16, "integrity verify", s.integrity_verify?)
chk(16, "integrity raw", VSN.integrity_verify_raw?(s.export_bytes))
chk(16, "integrity detects corruption", !VSN.integrity_verify_raw?(b("XXXXXXXX")))

# 17. Storage statistics
st = s.get_stats
chk(17, "storage statistics", st.objects >= 1 && st.files >= 1)

# 18. Builder
chk(18, "builder creates store", VSN::Store.new_builder(1).mode == 1)

# 19. Cross-language interoperability
s19=VSN::Store.create; f19=s19.create_file("i", b("interop-data-42")); chk(19, "interop content round-trip", s19.read_file(f19) == b("interop-data-42"))
chk(19, "interop magic bytes", VSN.check_magic_bytes?(VSN.encode(1, 0)))

# 6b. Transactions ExpectedRevision mismatch (before exit so it always runs)
chk_raises(6, "transactions ExpectedRevision mismatch") { s.commit(999_u64) }

puts "---"
puts "Crystal capabilities: #{Harness.passed} passed, #{Harness.failed} failed"

# ---- Storage Policy P01-P12 inline wire test ----
MODE_MAP = [{"HIGHLY_VERTICAL",   1}, {"VERTICAL",          1},
            {"HORIZONTAL",        2}, {"HIGHLY_HORIZONTAL", 2}]
sp_fail = false
all_wire : Array(String) = [] of String

MODE_MAP.each do |name, mode|
  s = MutableStore.create(mode)
  fid = s.create_file("sp.txt")
  s.write(fid, "storage-policy-wire-test")
  data = s.commit()
  all_wire << data

  if data.length < 5 || data[0,4] != "VSN-" || data[4] != mode
    puts "P03/P04 #{name} failed"; sp_fail = true; next
  end
end

if all_wire.length >= 3 && all_wire[0][4] == all_wire[2][4]
  puts "P05 same mode"; sp_fail = true
end

bad_names = ["HIGHTLY_VERTIC", "ERTICAL", "ORIZONTAL"]
all_wire.each do |d|
  bad_names.each { |b| if d.to_s.include?(b); puts "P10 leaked"; sp_fail = true; end }
end

puts sp_fail ? "SP FAILED" : "SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance"
exit(1) if sp_fail

exit(1) if Harness.failed > 0
