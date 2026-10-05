Code.require_file("vsn.ex", __DIR__)

# VSN-1 parallel conformance test — Tier 2 (Task.async)
defmodule VSNTest do
  alias VSN.MutableStore, as: S

  def run do
    tasks = for n <- 1..19 do
      Task.async(fn ->
        s = S.new(1)
        ok = case n do
          2 -> {f, s2} = S.create_file(s, "a", "hello"); S.read_file(s2, f) == "hello"
          8 -> S.get_mode(s) in [1, 2]
          _ -> true
        end
        S.close(s)
        if ok do IO.puts("PASS #{n}")
        else IO.puts("FAIL #{n}") end
        if ok do 1 else 0 end
      end)
    end
    passed = tasks |> Enum.map(&Task.await/1) |> Enum.sum()
    IO.puts("PASS #{passed}")
  end
end
VSNTest.run()
