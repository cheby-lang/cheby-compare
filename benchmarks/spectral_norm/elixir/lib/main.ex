defmodule Main do
  @moduledoc "Spectral norm: 10 rounds of the power method on A^T A, with vectors as lists of floats."

  @compile {:inline, a: 2}

  def main do
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()

    indices = Enum.to_list(0..(n - 1)//1)
    u0 = List.duplicate(1.0, n)
    {u, v} = rounds(10, u0, u0, indices)
    {vbv, vv} = dots(u, v, 0.0, 0.0)

    result = if vv == 0.0, do: 0, else: round(:math.sqrt(vbv / vv) * 1.0e9)
    IO.write([Integer.to_string(result), "\n"])
  end

  defp rounds(0, u, v, _indices), do: {u, v}

  defp rounds(k, u, _v, indices) do
    v = times_ata(u, indices)
    u = times_ata(v, indices)
    rounds(k - 1, u, v, indices)
  end

  defp times_ata(x, indices), do: x |> times_a(indices) |> times_at(indices)

  defp times_a(x, indices), do: Enum.map(indices, fn i -> row_sum(i, x, 0, 0.0) end)

  defp times_at(x, indices), do: Enum.map(indices, fn i -> col_sum(i, x, 0, 0.0) end)

  defp row_sum(_i, [], _j, s), do: s
  defp row_sum(i, [xj | xs], j, s), do: row_sum(i, xs, j + 1, s + a(i, j) * xj)

  defp col_sum(_i, [], _j, s), do: s
  defp col_sum(i, [xj | xs], j, s), do: col_sum(i, xs, j + 1, s + a(j, i) * xj)

  defp a(i, j), do: 1.0 / (div((i + j) * (i + j + 1), 2) + i + 1)

  defp dots([], [], vbv, vv), do: {vbv, vv}
  defp dots([ui | us], [vi | vs], vbv, vv), do: dots(us, vs, vbv + ui * vi, vv + vi * vi)
end
