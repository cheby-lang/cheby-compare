defmodule Main do
  @moduledoc "word_freq: counts the words of a file and prints the 20 most frequent."

  @top 20

  def main do
    [path | _] = :init.get_plain_arguments()
    text = File.read!(List.to_string(path))
    words = String.split(text)

    counts = Enum.reduce(words, %{}, fn word, acc -> Map.update(acc, word, 1, &(&1 + 1)) end)

    top =
      counts
      |> Enum.sort(fn {w1, c1}, {w2, c2} -> c1 > c2 or (c1 == c2 and w1 <= w2) end)
      |> Enum.take(@top)

    IO.write([
      "total #{length(words)}\n",
      "distinct #{map_size(counts)}\n",
      Enum.map(top, fn {word, count} -> "#{count} #{word}\n" end)
    ])
  end
end
