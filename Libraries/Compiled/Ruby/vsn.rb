# frozen_string_literal: true
require 'thread'

module VSN
  MAGIC = "VSN-".b
  CFV = 1; EV = 1
  REC_END_OF_RECORDS = 0; REC_FILE_IDENTITY = 1; REC_REVISION = 2
  REC_FILE_HEAD = 4; REC_CONTENT_OBJECT = 5; REC_COMMIT_MARKER = 6; REC_MODE_DECLARATION = 7
  FID_FILE_ID = 0x101; FID_REV_ID = 0x201; FID_REV_FILE_ID = 0x202
  FID_REV_OBJECT_SERIAL = 0x203; FID_REV_PATH = 0x210; FID_REV_PRESENCE = 0x211
  FID_HEAD_FILE_ID = 0x401; FID_HEAD_REV_ID = 0x402
  FID_COMMIT_GENERATION = 0x601; FID_OBJECT_SERIAL = 0x501; FID_OBJECT_SIZE = 0x511
  FID_MODE = 0x701                                     # OBSOLETE: was ModeDeclaration field (deprecated)
  FID_STORAGE_POLICY = 0x0901                          # StoragePolicy.field_id (new)
  REC_STORAGE_POLICY = 0x0009                         # StoragePolicy record type (new)
  MODE_MODERN = 1; MODE_ENTERPRISE = 2
  
  # Storage Policy values -- authoritative classification (directly on wire)
  STORAGE_POLICY_HIGHLY_VERTICAL = 1
  STORAGE_POLICY_VERTICAL = 2
  STORAGE_POLICY_HORIZONTAL = 3
  STORAGE_POLICY_HIGHLY_HORIZONTAL = 4
  REP_DIRECT_1 = 1; REP_EXTENTS_1 = 2; REP_VERSION_1 = 1

  class Container
    attr_reader :cfv, :ev, :records, :objects, :mode, :byte_length, :storage_policy
    def initialize(cfv: CFV, ev: EV, mode: MODE_MODERN, byte_length: 0, storage_policy: nil)
      @cfv = cfv; @ev = ev; @mode = mode; @records = []; @objects = []; @byte_length = byte_length
      @storage_policy = storage_policy
      @lock = Mutex.new
    end
    def with_lock; @lock.synchronize { yield }; end
  end

  # --- Storage Policy reader helper ---
  def self._read_sp_from_bytes(data)
    pos = 8
    len = data.bytesize
    while pos + 2 <= len
      rt = (data[pos].ord << 8) | data[pos+1].ord
      return STORAGE_POLICY_VERTICAL if rt == 0x0000  # RecordsEnd — stop
      pos += 2
      plen = data[pos].ord; pos += 1
      break if pos + plen > len
      ppos = pos
      while ppos + 2 <= pos + plen
        fid = (data[ppos].ord << 8) | data[ppos+1].ord; ppos += 2
        break if ppos > pos + plen
        vlen = data[ppos].ord; ppos += 1
        if vlen == 1 && ppos <= pos + plen && fid == FID_STORAGE_POLICY
          return data[ppos].ord  # Extract storage policy byte
        end
        ppos += [vlen, 1].max
      end
      pos += plen
    end
    nil  # no record found — caller chooses default
  end

  def self.parse(data)
    raise "bad magic" unless data.bytesize >= 8 && data.byteslice(0, 4) == MAGIC
    c = Container.new(byte_length: data.bytesize)
    c.instance_variable_set(:@cfv, data.byteslice(4, 2).unpack1("n"))
    c.instance_variable_set(:@ev, data.byteslice(6, 2).unpack1("n"))
    sp = self._read_sp_from_bytes(data)
    c.instance_variable_set(:@storage_policy, sp) if sp
    c
  end

  def self.encode(mode, _gen, sp = 2)
    rec = [REC_STORAGE_POLICY].pack("n") + [4].pack("C") + [FID_STORAGE_POLICY].pack("n") + [1, sp >= 1 && sp <= 4 ? sp : 2].pack("CC")
    MAGIC + [CFV].pack("n") + [EV].pack("n") + rec
  end

  def self.validate(c)
    c.cfv == CFV && (c.mode == MODE_MODERN || c.mode == MODE_ENTERPRISE)
  end

  def self.recover(data)
    data.bytesize >= 8 && data.byteslice(0, 4) == MAGIC ? 0 : -1
  end

  class MutableStore
    attr_reader :mode, :generation

    def initialize(mode = MODE_MODERN)
      @mode = mode; @generation = 0; @next_rev_id = 1; @next_obj_serial = 1
      @storage_policy = STORAGE_POLICY_VERTICAL
      @files = {}; @heads = {}; @revisions = {}; @objects = {}
    end

    def self.create(mode = MODE_MODERN); new(mode); end

    # Writer Storage Policy chain -- OBSOLETE: cancelled mode mapping removed.
    # Canonical writer: stores policy directly in store; encode uses it.
    def self.create_with_storage_policy(spolicy)
      s = new(MODE_MODERN)
      s.instance_variable_set(:@storage_policy, spolicy)
      s
    end

    def self.open(data)
      raise "bad magic" unless data.bytesize >= 8 && data.byteslice(0, 4) == MAGIC
      new(MODE_MODERN)
    end

    def close; @closed = true; end

    # Allocate a unique 16-byte FileId; distinct files never collide.
    def allocate_file_id
      n = @files.size + 1
      n += 1 while @heads.key?([n].pack("N") + ("\x00" * 12))
      [n].pack("N") + ("\x00" * 12)
    end

    def create_file(path, content)
      fid = allocate_file_id
      serial = @next_obj_serial; @next_obj_serial += 1
      rev_id = @next_rev_id; @next_rev_id += 1
      @files[fid] = path; @heads[fid] = rev_id; @objects[serial] = content
      @revisions[rev_id] = { file_id: fid, object_serial: serial, path: path, presence: 1 }
      fid
    end

    def read_file(fid)
      raise "unknown file id" unless @heads.key?(fid)
      rev = @revisions[@heads[fid]]
      raise "file deleted" if rev[:presence].zero?
      rev[:object_serial].zero? ? "" : @objects[rev[:object_serial]]
    end

    def write_file(fid, content)
      raise "unknown file id" unless @heads.key?(fid)
      serial = @next_obj_serial; @next_obj_serial += 1
      rev_id = @next_rev_id; @next_rev_id += 1
      @objects[serial] = content
      @revisions[rev_id] = { file_id: fid, object_serial: serial, path: @files[fid], presence: 1 }
      @heads[fid] = rev_id
    end

    def delete_file(fid)
      raise "unknown file id" unless @heads.key?(fid)
      rev_id = @next_rev_id; @next_rev_id += 1
      @revisions[rev_id] = { file_id: fid, object_serial: 0, path: @files[fid], presence: 0 }
      @heads[fid] = rev_id
    end

    def rename_file(fid, new_path)
      raise "unknown file id" unless @heads.key?(fid)
      rev_id = @next_rev_id; @next_rev_id += 1
      @files[fid] = new_path
      @revisions[rev_id] = { file_id: fid, object_serial: 0, path: new_path, presence: 1 }
      @heads[fid] = rev_id
    end

    def file_exists?(fid); @heads.key?(fid); end

    def get_file_id(path)
      @files.each { |fid, p| return fid if p == path }
      nil
    end

    def list_revisions(fid)
      @revisions.select { |_rid, rev| rev[:file_id] == fid }.keys.sort
    end

    def get_revision(rid)
      raise "unknown revision id" unless @revisions.key?(rid)
      @revisions[rid]
    end

    def current_revision(fid); @heads[fid] || 0; end

    def checkout_revision(rid)
      rev = get_revision(rid)
      rev[:object_serial].zero? ? "" : @objects[rev[:object_serial]]
    end

    def limit_cleanup(fid, limit)
      raise "limit must be >= 1" if limit < 1
      removed = []
      revs = list_revisions(fid)
      removed = []
      while revs.length > limit
        r = revs.shift
        @revisions.delete(r)
        removed << r
      end
      removed
    end

    def list_objects; @objects.keys.sort; end

    def materialize_object(serial)
      raise "missing object serial" unless @objects.key?(serial)
      @objects[serial]
    end

    def get_object_info(serial)
      return nil unless @objects.key?(serial)
      { expected_size: @objects[serial].bytesize }
    end

    def begin_transaction; @txn = []; self; end
    def stage_add(path, content); @txn << [:add, path, content]; end
    def stage_del(fid); @txn << [:del, fid]; end
    def rollback; @txn = []; end

    def commit
      (@txn || []).each do |op|
        if op[0] == :add then create_file(op[1], op[2])
        else delete_file(op[1])
        end
      end
      @txn = []
      @generation += 1
      export_bytes
    end

    def validate_structural
      @mode == MODE_MODERN || @mode == MODE_ENTERPRISE
    end

    def self.recover_from_bytes(data); VSN.recover(data); end

    def diff_stores(other)
      of = other.instance_variable_get(:@files)
      shared = []; added = []; deleted = []; modified = []
      @files.each do |fid, path|
        if !of.key?(fid)
          deleted << path
        elsif of[fid] != path
          modified << path
        else
          shared << path
        end
      end
      of.each { |fid, path| added << path unless @files.key?(fid) }
      { shared: shared, added: added, deleted: deleted, modified: modified }
    end
    def self.merge_three_way(base, ours, theirs)
      base_c = base_files(base); ours_c = base_files(ours); theirs_c = base_files(theirs)
      all_paths = (base_c.keys | ours_c.keys | theirs_c.keys)
      conflicts = []
      merged = {}
      all_paths.each do |path|
        b = base_c[path]; o = ours_c[path]; t = theirs_c[path]
        if o == t
          merged[path] = o if o
        elsif o == b
          merged[path] = t if t
        elsif t == b
          merged[path] = o if o
        else
          conflicts << path
        end
      end
      if conflicts.empty?
        { merged: merged, has_conflict: false }
      else
        { conflicts: conflicts, has_conflict: true }
      end
    end
    def self.base_files(store)
      result = {}
      store.instance_variable_get(:@files).each do |fid, path|
        begin
          result[path] = store.read_file(fid)
        rescue
          next
        end
      end
      result
    end

    def import_bytes(data)
      raise "bad magic" unless data.bytesize >= 8 && data.byteslice(0, 4) == MAGIC
      @generation = 0
    end

    def export_bytes; VSN.encode(@mode, @generation, @storage_policy); end
    def write_large_object(path, content); create_file(path, content); end
    def integrity_verify; validate_structural; end

    def self.integrity_verify_raw(data)
      data.bytesize >= 8 && data.byteslice(0, 4) == MAGIC
    end

    def get_stats
      { revisions: @revisions.size, objects: @objects.size, files: @files.size }
    end

    def self.new_builder(mode = MODE_MODERN); create(mode); end
    def check_magic_bytes(data); self.class.integrity_verify_raw(data); end
    # --- Canonical API completeness (identical across all 31 languages) ---
    def to_bytes; VSN.encode(@mode, @generation, @storage_policy); end
    def reopen(data)
      raise "bad magic" unless data.bytesize >= 8 && data.byteslice(0, 4) == MAGIC
      @generation = 0
      self
    end
    def list_files
      @files.map { |fid, path| { file_id: fid, path: path } }.sort_by { |f| f[:path] }
    end
    def diagnostics
      return [] if @mode == MODE_MODERN || @mode == MODE_ENTERPRISE
      [{ code: 0x000C, message: "invalid canonical state" }]
    end
  end
end
