defmodule Main do
  @moduledoc "Fannkuch-redux: counts pancake flips over every permutation of 0..n-1, as lists."

  def main do
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()

    {checksum, max_flips} = fannkuch(max(n, 1))

    IO.write([
      Integer.to_string(checksum),
      "\nPfannkuchen(",
      Integer.to_string(n),
      ") = ",
      Integer.to_string(max_flips),
      "\n"
    ])
  end

  defp fannkuch(n) do
    perm1 = Enum.to_list(0..(n - 1))
    count = Tuple.duplicate(0, n)
    loop(perm1, count, n, n, 0, 0, 0)
  end

  # count is a tuple indexed from 0 with elem/2 and put_elem/3.
  defp loop(perm1, count, r, n, max_flips, checksum, perm_index) do
    count = reset(r, count)
    flips = flips(perm1, 0)
    max_flips = max(max_flips, flips)
    checksum = if rem(perm_index, 2) == 0, do: checksum + flips, else: checksum - flips
    next(perm1, count, 1, n, max_flips, checksum, perm_index)
  end

  # Step 1: count[r - 1] = r while r != 1.
  defp reset(1, count), do: count
  defp reset(r, count), do: reset(r - 1, put_elem(count, r - 1, r))

  # Step 2: reverse the first k + 1 elements until 0 is in front.
  defp flips([0 | _], flips), do: flips

  defp flips([k | _] = perm, flips) do
    {front, back} = Enum.split(perm, k + 1)
    flips(Enum.reverse(front, back), flips + 1)
  end

  # Step 3: rotate the first r + 1 elements left by one and step the counters.
  defp next(_perm1, _count, n, n, max_flips, checksum, _perm_index), do: {checksum, max_flips}

  defp next(perm1, count, r, n, max_flips, checksum, perm_index) do
    {[first | rest], back} = Enum.split(perm1, r + 1)
    rotated = rest ++ [first | back]
    c = elem(count, r) - 1
    count = put_elem(count, r, c)

    if c > 0 do
      loop(rotated, count, r, n, max_flips, checksum, perm_index + 1)
    else
      next(rotated, count, r + 1, n, max_flips, checksum, perm_index)
    end
  end
end
