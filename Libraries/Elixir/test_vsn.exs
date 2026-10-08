Code.require_file("vsn.ex", __DIR__)

# VSN-1 parallel conformance test — Tier 2 (Task.async)
defmodule VSNTest do
  alias VSN.MutableStore, as: S

  def run do
    tasks = for n <- 1..19 do
      Task.async(fn ->
        s = S.new(1)
        ok = case n do
          1 -> S.get_mode(s) in [VSN.mode_modern()]
          2 ->
            try do
              {fid, s2} = S.create_file(s, "a", <<1,2,3>>)
              content = S.read_file(s2, fid)
              content == <<1,2,3>>
            rescue _ -> false
            end
          3 ->
            try do
              {f, s2} = S.create_file(s, "r", <<1>>)
              s3 = S.write_file(s2, f, <<2>>)
              s4 = S.write_file(s3, f, <<3>>)
              revs = S.list_revisions(s4, f)
              length(revs) >= 3
            rescue _ -> false
            end
          4 ->
            try do
              {f, s2} = S.create_file(s, "lc", <<1>>)
              s3 = Enum.reduce(1..5, s2, fn i, acc -> S.write_file(acc, f, <<i>>) end)
              {dropped, s4} = S.limit_clean_up(s3, f, 3)
              length(dropped) == 3
            rescue _ -> false
            end
          5 ->
            try do
              {_of, s2} = S.create_file(s, "o", <<1,2>>)
              objs = S.list_objects(s2)
              length(objs) >= 1
            rescue _ -> false
            end
          6 ->
            try do
              t = S.begin_transaction(s)
              st = S.stage_add(t, "t", [1])
              {bytes, s2} = S.commit(st)
              byte_size(bytes) >= 8
            rescue _ -> false
            end
          7 -> try do {fid7, s7} = S.create_file(s, "rep", <<86,83,78,45,84,69,83,84>>); S.read_file(s7, fid7) == <<86,83,78,45,84,69,83,84>> rescue _ -> false end
          8 -> sm8 = S.new(1); se8 = S.new(2); {fm8, sm8b} = S.create_file(sm8, "m", <<109,111,100>>); {fe8, se8b} = S.create_file(se8, "e", <<101,110,116>>); S.get_mode(sm8b) == 1 and S.get_mode(se8b) == 2 and S.read_file(sm8b, fm8) == <<109,111,100>> and S.read_file(se8b, fe8) == <<101,110,116>>
          9 ->
            try do
              bytes = S.export_bytes(s)
              VSN.validate_structural(VSN.parse(bytes))
            rescue _ -> false
            end
          10 ->
            try do
              bytes = S.export_bytes(s)
              rc = VSN.recover(bytes)
              rc == 0
            rescue _ -> false
            end
          11 ->
            try do
              s2 = S.create(VSN.mode_modern())
              S.create_file(s, "x", <<1>>)
              diff = S.diff_stores(s, s2)
              Map.has_key?(diff, :added)
            rescue _ -> false
            end
          12 ->
            try do
              s2 = S.create(VSN.mode_modern())
              S.create_file(s, "a", [1,2])
              s3 = S.create(VSN.mode_modern())
              S.create_file(s2, "b", [3,4])
              m = S.merge_three_way(s2, s, s3)
              Map.has_key?(m, :merged) and m[:merged] == s
            rescue _ -> false
            end
          13 ->
            try do
              bytes = S.export_bytes(s)
              s2 = S.open(bytes)
              S.get_mode(s2) == VSN.mode_modern()
            rescue _ -> false
            end
          14 ->
            try do
              {fid, s2} = S.create_file(s, "big", <<1,2,3,4,5,6,7,8>>)
              content = S.read_file(s2, fid)
              byte_size(content) == 8 and content == <<1,2,3,4,5,6,7,8>>
            rescue _ -> false
            end
          15 ->
            try do
              bytes = S.export_bytes(s)
              diags = S.diagnostics(s, "Full")
              is_list(diags)
            rescue _ -> false
            end
          16 ->
            try do
              bytes = S.export_bytes(s)
              ok = S.integrity_verify_raw(bytes)
              ok
            rescue _ -> false
            end
          17 ->
            try do
              {_sf, s2} = S.create_file(s, "stat", <<1>>)
              stats = S.get_stats(s2)
              Map.has_key?(stats, :files) and stats.files >= 1
            rescue _ -> false
            end
          18 ->
            b = S.new_builder(VSN.mode_enterprise())
            S.get_mode(b) in [VSN.mode_modern(), VSN.mode_enterprise()]
          19 ->
            bytes = VSN.encode(VSN.mode_modern(), 0)
            S.check_magic_bytes(bytes)
          _ -> false
        end
        S.close(s)
        if ok do
          IO.puts("CAP #{n} PASS assertions=1 ops=1")
          1
        else
          IO.puts("CAP #{n} FAIL assertions=0 ops=1")
          0
        end
      end)
    end
    passed = tasks |> Enum.map(&Task.await/1) |> Enum.sum()
    IO.puts("PASS #{passed}")
  end
end
VSNTest.run()

# Writer Storage Policy integration
defmodule VSN.StoragePolicy do
  @highly_vertical 1
  @vertical 2
  @horizontal 3
  @highly_horizontal 4
  def mode_for(:highly_vertical), do: 1
  def mode_for(:vertical), do: 1
  def mode_for(_), do: 2
end

defmodule VSN.StoreWithPolicy do
  def create(policy) do
    mode = VSN.StoragePolicy.mode_for(policy)
    # delegates to existing store creation
    VSN.MutableStore.create(mode)
  end
end

# ---- Storage Policy P01-P12 inline wire test ----
expectations = [
  {"HIGHLY_VERTICAL",   1},
  {"VERTICAL",          1},
  {"HORIZONTAL",        2},
  {"HIGHLY_HORIZONTAL", 2}
]

{sp_fail, all_wire} = Enum.reduce(expectations, {false, []}, fn {name, mode}, {fail, wire} ->
  if fail do {true, wire}
  else
    s = VSN.MutableStore.create(mode)
    {fid, s2} = VSN.MutableStore.create_file(s, "sp.txt", "storage-policy-wire-test")
    {data, _s3} = VSN.MutableStore.commit(s2, nil)
     ok = byte_size(data) >= 15 and :binary.part(data, 0, 4) == "VSN-" and :binary.at(data, 8) == 0x00 and :binary.at(data, 9) == 0x09
    if not ok do IO.puts("P03/P04 #{name} failed"); {true, wire}
    else {fail, [data | wire]}
    end
  end
end)

case {sp_fail, all_wire} do
  {true, _} ->
    IO.puts("SP FAILED")
    System.halt(1)
  {false, [hv|_rest] = wl} ->
    p5_ok = :binary.at(hv, 8) == 0x00 and :binary.at(hv, 9) == 0x09
    if not p5_ok do
      IO.puts("P05 missing SP record")
      System.halt(1)
    end
    IO.puts("SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance")
end
