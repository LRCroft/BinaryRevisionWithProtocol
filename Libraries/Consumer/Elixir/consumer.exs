# VSN-1 independent consumer (Elixir) -- Storage Policy round-trip.
# Uses the library's VSN.encode/3 (wire-out) + VSN.parse/1 (wire-in).
Code.require_file("../../Elixir/vsn.ex", __DIR__)

defmodule Consumer do
  def sig(b) do
    l = :binary.bin_to_list(b)
    n = length(l)
    Enum.any?(0..max(0, n - 6), fn i ->
      Enum.at(l, i) == 0 and Enum.at(l, i + 1) == 9 and Enum.at(l, i + 2) == 4 and
        Enum.at(l, i + 3) == 9 and Enum.at(l, i + 4) == 1 and Enum.at(l, i + 5) == 1
    end)
  end

  def main do
    bad =
      Enum.reduce(1..4, false, fn p, acc ->
        b = VSN.encode(1, 0, p)
        c = VSN.parse(b)
        if sig(b) and c.storage_policy == p do
          acc
        else
          IO.puts("FAIL p=#{p} sig=#{sig(b)} got=#{inspect(c.storage_policy)}")
          true
        end
      end)
    if bad do
      IO.puts("CONSUMER ELIXIR FAIL")
      System.halt(1)
    else
      IO.puts("CONSUMER ELIXIR PASS")
    end
  end
end

Consumer.main()
