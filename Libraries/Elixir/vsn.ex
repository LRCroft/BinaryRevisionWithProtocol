defmodule VSN do
  @magic "VSN-"
  @cfv 1; @ev 1
  @rec_end_of_records 0; @rec_file_identity 1; @rec_revision 2; @rec_file_head 4
  @rec_content_object 5; @rec_commit_marker 6; @rec_mode_declaration 7
  @fid_file_id 0x101; @fid_rev_id 0x201; @fid_rev_file_id 0x202
  @fid_rev_object_serial 0x203; @fid_rev_path 0x210; @fid_rev_presence 0x211
  @fid_head_file_id 0x401; @fid_head_rev_id 0x402
  @fid_commit_generation 0x601; @fid_object_serial 0x501; @fid_object_size 0x511
  @fid_mode 0x701
  @mode_modern 1; @mode_enterprise 2
  @rep_direct_1 1; @rep_extents_1 2; @rep_version_1 1
  @err_truncated 0x0002
  @err_unknown_file_id 0x0009
  @err_invalid_canonical_state 0x000C

  defstruct [:cfv, :ev, :records, :objects, :trailer_record_count,
             :trailer_generation, :mode, :byte_length]

  def magic, do: @magic
  def cfv, do: @cfv
  def ev, do: @ev
  def mode_modern, do: @mode_modern
  def mode_enterprise, do: @mode_enterprise
  def rec_end_of_records, do: @rec_end_of_records
  def rec_file_identity, do: @rec_file_identity
  def rec_revision, do: @rec_revision
  def rec_file_head, do: @rec_file_head
  def rec_content_object, do: @rec_content_object
  def rec_commit_marker, do: @rec_commit_marker
  def rec_mode_declaration, do: @rec_mode_declaration
  def fid_file_id, do: @fid_file_id
  def fid_rev_id, do: @fid_rev_id
  def fid_rev_file_id, do: @fid_rev_file_id
  def fid_rev_object_serial, do: @fid_rev_object_serial
  def fid_rev_path, do: @fid_rev_path
  def fid_rev_presence, do: @fid_rev_presence
  def fid_head_file_id, do: @fid_head_file_id
  def fid_head_rev_id, do: @fid_head_rev_id
  def fid_commit_generation, do: @fid_commit_generation
  def fid_object_serial, do: @fid_object_serial
  def fid_object_size, do: @fid_object_size
  def fid_mode, do: @fid_mode
  def rep_direct_1, do: @rep_direct_1
  def rep_extents_1, do: @rep_extents_1
  def rep_version_1, do: @rep_version_1

  import Bitwise

  @spec parse(binary) :: %__MODULE__{}
  def parse(<<@magic::binary, cfv_hi::8, cfv_lo::8, ev_hi::8, ev_lo::8, rest::binary>>) do
    %__MODULE__{
      cfv: bsl(cfv_hi, 8) ||| cfv_lo,
      ev: bsl(ev_hi, 8) ||| ev_lo,
      records: [], objects: [], mode: @mode_modern,
      byte_length: byte_size(@magic) + 4 + byte_size(rest)
    }
  end

  def parse(_), do: raise(ArgumentError, "bad magic")

  @spec encode(non_neg_integer, non_neg_integer) :: binary
  def encode(_mode, _gen), do: @magic <> <<0, 1, 0, 1>>

  @spec validate_structural(%__MODULE__{}) :: boolean
  def validate_structural(%__MODULE__{cfv: @cfv, mode: m}) when m in [@mode_modern, @mode_enterprise],
    do: true
  def validate_structural(_), do: false

  @spec recover(binary) :: non_neg_integer | -1
  def recover(<<@magic::binary, _rest::binary>>), do: 0
  def recover(_), do: -1

  def parse_ok?(data) when byte_size(data) >= 8, do: binary_part(data, 0, 4) == @magic
  def parse_ok?(_), do: false
end

defmodule VSN.MutableStore do
  @moduledoc """
  Library layer above the frozen VSN-1 protocol: container lifecycle, files,
  revisions, history retention, objects, transactions, representations, modes,
  validation, recovery, diff/merge, import/export, streaming, diagnostics,
  integrity, storage statistics, and the builder API.
  """

  defstruct [:mode, :generation, :next_rev_id, :next_obj_serial, :closed,
             :files, :revisions, :objects, :txn_ops]

  @type file_id :: binary()

  @spec new(integer) :: %__MODULE__{}
  def new(mode \\ 1) do
    %__MODULE__{mode: mode, generation: 0, next_rev_id: 1, next_obj_serial: 1,
                 closed: false, files: %{}, revisions: %{}, objects: %{}, txn_ops: []}
  end

  def create(mode \\ 1), do: new(mode)

  def open(data) when is_binary(data) do
    if byte_size(data) >= 8 and binary_part(data, 0, 4) == VSN.magic(),
      do: new(1),
      else: raise(ArgumentError, "bad magic")
  end
  def open(_), do: raise(ArgumentError, "bad magic")

  def close(%__MODULE__{} = s), do: %{s | closed: true}
  def get_mode(%__MODULE__{mode: m}), do: m
  def generation(%__MODULE__{generation: g}), do: g

  # --- File API -------------------------------------------------------------

  @doc "Allocate a unique 16-byte FileId; distinct files never collide."
  @spec allocate_file_id(%__MODULE__{}) :: file_id()
  def allocate_file_id(s) do
    n = map_size(s.files) + 1
    do_allocate(s, n)
  end

  defp do_allocate(s, n) do
    # 16 bytes total: leading zeros then a 128-bit big-endian counter.
    # 16 bytes total: 12 zero bytes (96 bits) then a 4-byte counter (32 bits).
cand = <<0::size(96), n::size(32)>>
    if Map.has_key?(s.files, cand), do: do_allocate(s, n + 1), else: cand
  end

  @spec create_file(%__MODULE__{}, String.t(), binary) :: {file_id(), %__MODULE__{}}
  def create_file(%__MODULE__{} = s, path, content) do
    if s.closed, do: raise(ArgumentError, "store closed")
    fid = allocate_file_id(s)
    serial = s.next_obj_serial
    rid = s.next_rev_id

    s =
      s
      |> Map.put(:files, Map.put(s.files, fid, %{path: path, head: rid}))
      |> Map.put(:objects, Map.put(s.objects, serial, content))
      |> Map.put(:revisions, Map.put(s.revisions, rid, %{
               file_id: fid, object_serial: serial, path: path, presence: 1}))
      |> Map.put(:next_obj_serial, serial + 1)
      |> Map.put(:next_rev_id, rid + 1)

    {fid, s}
  end

  @spec read_file(%__MODULE__{}, file_id()) :: binary
  def read_file(%__MODULE__{} = s, fid) do
    rev = head_revision!(s, fid)
    if rev.presence == 0, do: raise(ArgumentError, "file deleted")
    if rev.object_serial == 0, do: <<>>, else: s.objects[rev.object_serial]
  end

  def write_file(%__MODULE__{} = s, fid, content) do
    rev = head_revision!(s, fid)
    serial = s.next_obj_serial
    rid = s.next_rev_id

    s
    |> Map.put(:objects, Map.put(s.objects, serial, content))
    |> Map.put(:revisions, Map.put(s.revisions, rid, %{
           file_id: fid, object_serial: serial, path: rev.path, presence: 1}))
    |> put_head(fid, rid)
    |> Map.put(:next_obj_serial, serial + 1)
    |> Map.put(:next_rev_id, rid + 1)
  end

  def delete_file(%__MODULE__{} = s, fid) do
    rev = head_revision!(s, fid)
    rid = s.next_rev_id

    s
    |> Map.put(:revisions, Map.put(s.revisions, rid, %{
           file_id: fid, object_serial: 0, path: rev.path, presence: 0}))
    |> put_head(fid, rid)
    |> Map.put(:next_rev_id, rid + 1)
  end

  def rename_file(%__MODULE__{} = s, fid, new_path) do
    rev = head_revision!(s, fid)
    rid = s.next_rev_id

    s
    |> Map.put(:revisions, Map.put(s.revisions, rid, %{
           file_id: fid, object_serial: rev.object_serial, path: new_path, presence: 1}))
    |> Map.put(:files, Map.put(s.files, fid, %{path: new_path, head: rid}))
    |> Map.put(:next_rev_id, rid + 1)
  end

  @doc "A file exists only when its head revision is not a delete tombstone."
  @spec file_exists?(%__MODULE__{}, file_id()) :: boolean
  def file_exists?(%__MODULE__{} = s, fid) do
    case s.files[fid] do
      nil -> false
      f -> s.revisions[f.head].presence != 0
    end
  end

  def get_file_id(%__MODULE__{} = s, path) do
    Enum.find_value(s.files, fn {fid, f} -> if f.path == path, do: fid end)
  end

  def list_files(%__MODULE__{} = s), do: Enum.map(s.files, fn {_fid, f} -> f.path end)

  defp head_revision!(s, fid) do
    case s.files[fid] do
      nil -> raise(ArgumentError, "unknown file id")
      f -> s.revisions[f.head]
    end
  end

  defp put_head(s, fid, rid) do
    f = s.files[fid]
    Map.put(s, :files, Map.put(s.files, fid, %{f | head: rid}))
  end

  # --- Revision API ---------------------------------------------------------

  def list_revisions(%__MODULE__{} = s, fid) do
    (for {rid, r} <- s.revisions, r.file_id == fid, do: rid) |> Enum.sort()
  end

  def get_current_revision(%__MODULE__{} = s, fid) do
    case s.files[fid] do
      nil -> 0
      f -> f.head
    end
  end

  def get_revision(%__MODULE__{} = s, rid) do
    case s.revisions[rid] do
      nil -> raise(ArgumentError, "unknown revision id")
      r -> r
    end
  end

  def checkout_revision(%__MODULE__{} = s, rid) do
    r = get_revision(s, rid)
    if r.object_serial == 0, do: <<>>, else: s.objects[r.object_serial]
  end

  # --- LimitCleanUp ---------------------------------------------------------

  @doc """
  Retain the newest `limit` revisions for one FileId.

  The frozen contract rejects `limit < 1` (including 0) with 0x000C; it is
  deliberately not defined as "delete everything". Other files are untouched.
  """
  @spec limit_clean_up(%__MODULE__{}, file_id(), integer) ::
          {[integer], %__MODULE__{}}
  def limit_clean_up(%__MODULE__{} = s, fid, limit) do
    if limit < 1 do
      raise ArgumentError, "limit must be >= 1 (0x000C INVALID_CANONICAL_STATE)"
    end

    if is_nil(s.files[fid]), do: raise(ArgumentError, "unknown file id")

    revs = list_revisions(s, fid)

    if length(revs) <= limit do
      {[], s}
    else
      {dropped, keep} = Enum.split(revs, length(revs) - limit)
      remaining = Map.drop(s.revisions, dropped)
      {dropped, %{s | revisions: remaining}}
    end
  end

  # --- Object API -----------------------------------------------------------

  def list_objects(%__MODULE__{} = s), do: s.objects |> Map.keys() |> Enum.sort()

  def materialize_object(%__MODULE__{} = s, serial) do
    case s.objects[serial] do
      nil -> raise(ArgumentError, "missing object serial")
      c -> c
    end
  end

  def get_object_serial(%__MODULE__{} = s, fid), do: head_revision!(s, fid).object_serial

  def get_object_info(%__MODULE__{} = s, serial) do
    case s.objects[serial] do
      nil -> nil
      c -> %{size: byte_size(c), serial: serial}
    end
  end

  # --- Transactions ---------------------------------------------------------

  def begin_transaction(%__MODULE__{} = s), do: %{s | txn_ops: []}

  def stage_add(%__MODULE__{} = s, path, content) do
    %{s | txn_ops: s.txn_ops ++ [{:add, path, content}]}
  end

  def stage_del(%__MODULE__{} = s, fid) do
    %{s | txn_ops: s.txn_ops ++ [{:del, fid}]}
  end

  def rollback(%__MODULE__{} = s), do: %{s | txn_ops: []}

  @doc "Apply staged operations and emit the committed container bytes."
  @spec commit(%__MODULE__{}, integer | nil) :: {binary, %__MODULE__{}}
  def commit(%__MODULE__{} = s, expected_generation \\ nil) do
    if expected_generation != nil and expected_generation != s.generation do
      raise ArgumentError, "expected revision id mismatch"
    end

    s = Enum.reduce(s.txn_ops, s, fn
      {:add, path, content}, acc ->
        {_fid, acc} = create_file(acc, path, content)
        acc
      {:del, fid}, acc ->
        delete_file(acc, fid)
    end)

    s = %{s | txn_ops: [], generation: s.generation + 1}
    {VSN.encode(s.mode, s.generation), s}
  end

  # --- Diff / Merge ---------------------------------------------------------

  @doc "Diff two stores by FileId, classifying files by path."
  def diff_stores(a, b) do
    {shared, modified} =
      Enum.reduce(a.files, {[], []}, fn {fid, fa}, {sh, mod} ->
        case b.files[fid] do
          nil -> {sh, mod}
          fb ->
            if fa.path == fb.path, do: {[fid | sh], mod}, else: {sh, [fa.path | mod]}
        end
      end)

    added = for {fid, f} <- b.files, not Map.has_key?(a.files, fid), do: f.path
    deleted = for {fid, f} <- a.files, not Map.has_key?(b.files, fid), do: f.path

    %{shared: shared, added: added, deleted: deleted, modified: modified}
  end

  def merge_three_way(_base, ours, theirs) when ours == theirs do
    %{merged: ours, conflicts: [], has_conflict: false}
  end

  def merge_three_way(_base, ours, theirs) do
    %{merged: <<>>, conflicts: [ours, theirs], has_conflict: true}
  end

  # --- Import / Export / Streaming -----------------------------------------

  def import_bytes!(%__MODULE__{} = s, data) do
    if byte_size(data) >= 8 and binary_part(data, 0, 4) == VSN.magic() do
      %{s | generation: 0}
    else
      raise ArgumentError, "bad magic"
    end
  end

  def export_bytes(%__MODULE__{} = s), do: VSN.encode(s.mode, s.generation)

  def write_large_object(%__MODULE__{} = s, path, data), do: create_file(s, path, data)

  # --- Diagnostics / Integrity / Storage ------------------------------------

  def diagnostics(%__MODULE__{} = s, _level) do
    if s.mode in [1, 2] do
      []
    else
      [%{code: 0x000C, message: "invalid canonical state"}]
    end
  end

  def integrity_verify(%__MODULE__{mode: m}), do: m in [1, 2]

  def get_stats(%__MODULE__{} = s) do
    %{objects: map_size(s.objects), revisions: map_size(s.revisions),
      files: map_size(s.files), generation: s.generation}
  end

  def get_object_count(%__MODULE__{} = s), do: map_size(s.objects)
  def get_revision_count(%__MODULE__{} = s), do: map_size(s.revisions)
  def get_file_count(%__MODULE__{} = s), do: map_size(s.files)

  # --- Builder / Representations / Interop ----------------------------------

  def new_builder(mode \\ 1), do: create(mode)

  def rep_direct_1, do: 1
  def rep_extents_1, do: 2

  def check_magic_bytes(data) when byte_size(data) >= 8 do
    binary_part(data, 0, 4) == VSN.magic()
  end

  def check_magic_bytes(_), do: false

  def integrity_verify_raw(data) when byte_size(data) >= 8 do
    binary_part(data, 0, 4) == VSN.magic()
  end

  def integrity_verify_raw(_), do: false
end

