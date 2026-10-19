defmodule Main do
  @moduledoc "Binary trees: builds and checks many perfect trees of {:node, left, right} tuples."

  import Bitwise

  @min_depth 4

  def main do
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()

    stretch = n + 1

    IO.write([
      "stretch tree of depth ",
      Integer.to_string(stretch),
      "\t check: ",
      Integer.to_string(check(make(stretch, nil))),
      "\n"
    ])

    long_lived = make(n, nil)
    depths(@min_depth, n)

    IO.write([
      "long lived tree of depth ",
      Integer.to_string(n),
      "\t check: ",
      Integer.to_string(check(long_lived)),
      "\n"
    ])
  end

  # make/2 is public only so that each leaf is a fresh heap tuple. A leaf written as
  # {:node, nil, nil}, or built from a nil passed between private functions, is folded by the
  # compiler into one shared literal, and the SPEC requires one allocation per node.
  @doc false
  def make(0, empty), do: {:node, empty, empty}

  def make(d, empty) do
    left = make(d - 1, empty)
    right = make(d - 1, empty)
    {:node, left, right}
  end

  defp check(nil), do: 0
  defp check({:node, left, right}), do: 1 + check(left) + check(right)

  defp depths(d, n) when d > n, do: :ok

  defp depths(d, n) do
    iterations = 1 <<< (n - d + @min_depth)
    total = repeat(iterations, d, 0)

    IO.write([
      Integer.to_string(iterations),
      "\t trees of depth ",
      Integer.to_string(d),
      "\t check: ",
      Integer.to_string(total),
      "\n"
    ])

    depths(d + 2, n)
  end

  defp repeat(0, _d, total), do: total
  defp repeat(i, d, total), do: repeat(i - 1, d, total + check(make(d, nil)))
end
