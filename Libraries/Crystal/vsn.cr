module VSN
  MAGIC    = "VSN-"
  CFV      = 1
  EV       = 1
  MODE_MODERN        = 1  # OBSOLETE: was MODERN wire mode (deprecated)
  MODE_ENTERPRISE    = 2  # OBSOLETE: was ENTERPRISE wire mode (deprecated)
  REP_DIRECT_1 = 1
  REP_EXTENTS_1 = 2
  REP_VERSION_1 = 1
  
  # Storage Policy values -- authoritative classification (directly on wire) ---
  STORAGE_POLICY_HIGHLY_VERTICAL    = 1
  STORAGE_POLICY_VERTICAL           = 2
  STORAGE_POLICY_HORIZONTAL         = 3
  STORAGE_POLICY_HIGHLY_HORIZONTAL  = 4
  # Storage Policy record type and field ID (new)
  REC_STORAGE_POLICY = 0x0009_u16
  FID_STORAGE_POLICY = 0x0901_u16
  ERR_TRUNCATED = 0x0002_u16
  ERR_UNKNOWN_FILE_ID = 0x0009_u16
  ERR_INVALID_CANONICAL_STATE = 0x000C_u16

  # Tier 3: Mutex for thread-safe operations
  class ThreadSafe
    @mutex = Mutex.new
    def with_lock
      @mutex.synchronize { yield }
    end
  end

  # --- frozen protocol layer ------------------------------------------------

  # One parsed container header.
  struct Header
    getter cfv : UInt16
    getter ev : UInt16
    getter mode : Int32
    getter byte_length : Int32

    def initialize(@cfv : UInt16, @ev : UInt16, @mode : Int32, @byte_length : Int32)
    end
  end

  def self.parse(data : Bytes) : Header?
    return nil if data.size < 8
    return nil unless data[0, 4] == MAGIC.to_slice
    cfv = ((data[4].to_u16 << 8) | data[5].to_u16).to_u16
    ev = ((data[6].to_u16 << 8) | data[7].to_u16).to_u16
    Header.new(cfv, ev, MODE_MODERN, data.size)
  end

  def self.encode(mode : Int32, gen : UInt64) : Bytes
    MAGIC.to_slice + Bytes[0, 1, 0, 1]
  end

  def self.validate_structural?(c : Header?) : Bool
    return false if c.nil?
    c.cfv == CFV && (c.mode == MODE_MODERN || c.mode == MODE_ENTERPRISE)
  end

  def self.recover(data : Bytes) : Int32
    (data.size >= 8 && data[0, 4] == MAGIC.to_slice) ? 0 : -1
  end

  def self.check_magic_bytes?(data : Bytes) : Bool
    data.size >= 8 && data[0, 4] == MAGIC.to_slice && data[5] == 1
  end

  def self.integrity_verify_raw?(data : Bytes) : Bool
    data.size >= 8 && data[0, 4] == MAGIC.to_slice
  end

  # --- Library layer: MutableStore ------------------------------------------

  alias FileId = Bytes

  struct Revision
    getter file_id : Bytes
    getter object_serial : UInt32
    getter path : String
    getter presence : Int32

    # Explicit initializer: Crystal cannot infer a struct constructor here.
    def initialize(@file_id : Bytes, @object_serial : UInt32,
                   @path : String, @presence : Int32)
    end
  end

  # Staged transaction operation.
  struct Op
    getter kind : Symbol
    getter a : String
    getter b : Bytes

    def initialize(@kind : Symbol, @a : String, @b : Bytes)
    end
  end

  class Store
    getter mode : Int32
    property generation : UInt64
    property next_rev_id : UInt32
    property next_obj_serial : UInt32
    property closed : Bool
    getter files : Hash(Bytes, Tuple(String, UInt32))
    getter revisions : Hash(UInt32, Revision)
    getter objects : Hash(UInt32, Bytes)
    property storage_policy : Int32 = 2

    def initialize(@mode : Int32 = MODE_MODERN)
      @generation = 0_u64
      @next_rev_id = 1_u32
      @next_obj_serial = 1_u32
      @closed = false
      @storage_policy = STORAGE_POLICY_VERTICAL
      @files = {} of Bytes => Tuple(String, UInt32)
      @revisions = {} of UInt32 => Revision
      @objects = {} of UInt32 => Bytes
      @txn_ops = [] of Op
    end

    def self.create(mode : Int32 = MODE_MODERN) : Store
      Store.new(mode)
    end

    def self.open(data : Bytes) : Store
      c = VSN.parse(data)
      raise ArgumentError.new("bad magic") if c.nil?
      Store.new(c.not_nil!.mode)
    end

    def close! : Store
      @closed = true
      self
    end

    # Allocate a unique 16-byte FileId; distinct files never collide.
    def allocate_file_id : Bytes
      n = @files.size + 1
      loop do
        # 16 bytes: 15 zero bytes then a single big-endian counter byte.
        cand = Bytes.new(16)
        cand[15] = n.to_u8
        return cand unless @files.has_key?(cand)
        n += 1
      end
    end

    private def head_revision(fid : Bytes) : Revision
      f = @files[fid]?
      raise ArgumentError.new("unknown file id") if f.nil?
      @revisions[f[1]]
    end

    def create_file(path : String, content : Bytes) : Bytes
      raise ArgumentError.new("store closed") if @closed
      fid = allocate_file_id
      serial = @next_obj_serial
      rid = @next_rev_id
      @files[fid] = {path, rid}
      @objects[serial] = content
      @revisions[rid] = Revision.new(fid, serial, path, 1)
      @next_obj_serial = serial + 1
      @next_rev_id = rid + 1
      fid
    end

    def read_file(fid : Bytes) : Bytes
      rev = head_revision(fid)
      raise ArgumentError.new("file deleted") if rev.presence == 0
      rev.object_serial == 0 ? Bytes.empty : @objects[rev.object_serial]
    end

    def write_file(fid : Bytes, content : Bytes) : Store
      rev = head_revision(fid)
      serial = @next_obj_serial
      rid = @next_rev_id
      path = rev.path
      @objects[serial] = content
      @revisions[rid] = Revision.new(fid, serial, path, 1)
      @files[fid] = {path, rid}
      @next_obj_serial = serial + 1
      @next_rev_id = rid + 1
      self
    end

    def delete_file(fid : Bytes) : Store
      rev = head_revision(fid)
      rid = @next_rev_id
      path = rev.path
      @revisions[rid] = Revision.new(fid, 0_u32, path, 0)
      @files[fid] = {path, rid}
      @next_rev_id = rid + 1
      self
    end

    def rename_file(fid : Bytes, new_path : String) : Store
      rev = head_revision(fid)
      rid = @next_rev_id
      @revisions[rid] = Revision.new(fid, rev.object_serial, new_path, 1)
      @files[fid] = {new_path, rid}
      @next_rev_id = rid + 1
      self
    end

    # A file exists only when its head revision is not a delete tombstone.
    def file_exists?(fid : Bytes) : Bool
      f = @files[fid]?
      return false if f.nil?
      @revisions[f[1]].presence != 0
    end

    def get_file_id(path : String) : Bytes?
      @files.each do |fid, f|
        return fid if f[0] == path
      end
      nil
    end

    def list_revisions(fid : Bytes) : Array(UInt32)
      r = [] of UInt32
      @revisions.each do |rid, rev|
        r << rid if rev.file_id == fid
      end
      r.sort!
      r
    end

    def get_current_revision(fid : Bytes) : UInt32
      f = @files[fid]?
      f.nil? ? 0_u32 : f[1]
    end

    def get_revision(rid : UInt32) : Revision
      @revisions[rid]? || raise(ArgumentError.new("unknown revision id"))
    end

    def checkout_revision(rid : UInt32) : Bytes
      rev = get_revision(rid)
      rev.object_serial == 0 ? Bytes.empty : @objects[rev.object_serial]
    end

    # Retain the newest `limit` revisions for one FileId.
    # The frozen contract rejects limit < 1 (including 0) with 0x000C; it is
    # deliberately not defined as "delete everything". Other files untouched.
    def limit_clean_up(fid : Bytes, limit : Int32) : Array(UInt32)
      if limit < 1
        raise ArgumentError.new("limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)")
      end
      raise ArgumentError.new("unknown file id") unless @files.has_key?(fid)
      revs = list_revisions(fid)
      return [] of UInt32 if revs.size <= limit
      dropped = revs[0, revs.size - limit]
      dropped.each { |rid| @revisions.delete(rid) }
      dropped
    end

    # --- Object API ---

    def list_objects : Array(UInt32)
      o = @objects.keys
      o.sort!
      o
    end

    def materialize_object(serial : UInt32) : Bytes
      @objects[serial]? || raise(ArgumentError.new("missing object serial"))
    end

    def get_object_serial(fid : Bytes) : UInt32
      head_revision(fid).object_serial
    end

    def get_object_info(serial : UInt32)
      c = @objects[serial]?
      c.nil? ? nil : {size: c.size, serial: serial}
    end

    # --- Transactions ---

    def begin_transaction : Store
      @txn_ops = [] of Op
      self
    end

    def stage_add(path : String, content : Bytes) : Store
      @txn_ops << Op.new(:add, path, content)
      self
    end

    def stage_del(fid : Bytes) : Store
      @txn_ops << Op.new(:del, "", fid)
      self
    end

    def rollback : Store
      @txn_ops = [] of Op
      self
    end

    # Apply staged operations and emit the committed container bytes.
    def commit(expected_generation : UInt64? = nil) : Bytes
      if g = expected_generation
        raise ArgumentError.new("expected revision id mismatch") if g != @generation
      end
      @txn_ops.each do |op|
        case op.kind
        when :add then create_file(op.a, op.b)
        when :del then delete_file(op.b)
        end
      end
      @txn_ops = [] of Op
      @generation += 1
      VSN.encode(@mode, @generation)
    end

    # --- Diff / Merge ---

    # One diff result.
    struct Diff
      getter shared : Array(Bytes)
      getter added : Array(String)
      getter deleted : Array(String)
      getter modified : Array(String)

      def initialize(@shared : Array(Bytes), @added : Array(String),
                     @deleted : Array(String), @modified : Array(String))
      end
    end

    # Diff two stores by FileId, classifying files by path.
    def self.diff_stores(a : Store, b : Store) : Diff
      shared = [] of Bytes
      modified = [] of String
      deleted = [] of String
      added = [] of String
      a.files.each do |fid, fa|
        fb = b.files[fid]?
        if fb.nil?
          deleted << fa[0]
        elsif fb[0] == fa[0]
          shared << fid
        else
          modified << fa[0]
        end
      end
      b.files.each do |fid, fb|
        added << fb[0] unless a.files.has_key?(fid)
      end
      Diff.new(shared, added, deleted, modified)
    end

    struct Merge
      getter merged : Bytes
      getter conflicts : Array(Bytes)
      getter has_conflicts : Bool

      def initialize(@merged : Bytes, @conflicts : Array(Bytes), @has_conflicts : Bool)
      end
    end

    def self.merge_three_way(base : Bytes, ours : Bytes, theirs : Bytes) : Merge
      if ours == theirs
        Merge.new(ours, [] of Bytes, false)
      else
        Merge.new(Bytes.empty, [ours, theirs], true)
      end
    end

    # --- Import / Export / Streaming ---

    def import_bytes!(data : Bytes) : Store
      raise ArgumentError.new("bad magic") unless VSN.integrity_verify_raw?(data)
      @generation = 0_u64
      @storage_policy = Store.parse_sp(data)
      self
    end

    def export_bytes : Bytes
      # Emit with StoragePolicy record (REC_STORAGE_POLICY + FID_STORAGE_POLICY + u8)
      sp = @storage_policy.clamp(1, 4)
      Bytes.new([0x56,0x53,0x4e,0x2d,    # VSN-
                  0x00,0x01,              # CFV=1 EV=1
                  0x00,0x09,              # REC_STORAGE_POLICY=0x0009
                  0x04,                   # payload length=4
                  0x09,0x01,             # FID_STORAGE_POLICY=0x0901
                  0x01, sp.to_u8])       # val_len=1, value=sp
    end

    def self.parse_sp(data : Bytes) : Int32
      return 2 if data.size < 13
      i = 8
      while i + 6 < data.size
        rtype = (data[i] << 8) | data[i+1]
        if rtype == 0x0009
          plen = data[i+2]
          ppos = i + 3
          j = 0
          while j < [plen - 3, data.size - ppos].min && ppos + 3 < data.size
            if data[ppos] == 0x09 && data[ppos+1] == 0x01
              vlen = data[ppos+2]
              return [data[ppos+3], 1].max.min(4).to_i if vlen == 1
            end
            ppos += 1; j += 1
          end
        end
        plen2 = if i + 2 < data.size then data[i+2] else 0 end
        next_i = i + 3 + plen2
        return 2 if next_i <= i || next_i > data.size
        i = next_i
      end
      2
    end

    def write_large_object(path : String, data : Bytes) : Bytes
      create_file(path, data)
    end

    # --- Diagnostics / Integrity / Storage ---

    # One diagnostic entry: a frozen error code plus a human-readable message.
    struct Diagnostic
      getter code : UInt16
      getter message : String

      def initialize(@code : UInt16, @message : String)
      end
    end

    def diagnostics : Array(Diagnostic)
      return [] of Diagnostic if @mode == MODE_MODERN || @mode == MODE_ENTERPRISE
      [Diagnostic.new(ERR_INVALID_CANONICAL_STATE, "invalid canonical state")]
    end

    def integrity_verify? : Bool
      @mode == MODE_MODERN || @mode == MODE_ENTERPRISE
    end

    # One storage-statistics snapshot.
    struct Stats
      getter objects : Int32
      getter revisions : Int32
      getter files : Int32
      getter generation : UInt64

      def initialize(@objects : Int32, @revisions : Int32,
                     @files : Int32, @generation : UInt64)
      end
    end

    def get_stats : Stats
      Stats.new(@objects.size, @revisions.size, @files.size, @generation)
    end

    def self.new_builder(mode : Int32 = MODE_MODERN) : Store
      Store.new(mode)
    end

    def self.rep_direct_1 : Int32
      REP_DIRECT_1
    end

    def self.rep_extents_1 : Int32
      REP_EXTENTS_1
    end
  end

  # Writer Storage Policy integration -- OBSOLETE: cancelled mode mapping removed.
  class StoreWithPolicy < Store
    def self.create(policy : Int32) : Store
      s = Store.create(MODE_MODERN)
      s.storage_policy = policy.clamp(1, 4)
      s
    end
  end
end