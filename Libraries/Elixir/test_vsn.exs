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
              Map.has_key?(m, :merged)
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
              {fid, s2} = S.create_file(s, "big", <<1,2,3,4,5>>)
              content = S.read_file(s2, fid)
              byte_size(content) == 5
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
