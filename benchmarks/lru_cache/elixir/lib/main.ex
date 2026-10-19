defmodule Main do
  @moduledoc """
  LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.

  Shape C of the spec: `entries` maps each key to `{value, tick}`, `by_tick` is a `:gb_trees`
  from each live tick to its key, and the smallest tick is the least recent entry.
  """

  @modulus 1_000_000_007
  @lehmer_m 2_147_483_647
  @lehmer_a 48_271
  @seed 42
  @hot_percent 80
  @key_space_factor 16

  defmodule Lru do
    @moduledoc "The cache: entries, the tick order and the clock."
    defstruct [:capacity, entries: %{}, by_tick: :gb_trees.empty(), clock: 0]
  end

  def main do
    [capacity, ops] =
      :init.get_plain_arguments()
      |> Enum.take(2)
      |> Enum.map(&(&1 |> List.to_string() |> String.to_integer()))

    hot = capacity
    cold = capacity * (@key_space_factor - 1)

    {cache, hits, misses, values} =
      run(ops, @seed, hot, cold, %Lru{capacity: capacity}, 0, 0, 0)

    checksum = checksum(:gb_trees.next(:gb_trees.iterator(cache.by_tick)), 1, 0)

    IO.write([
      "hits #{hits}\n",
      "misses #{misses}\n",
      "values #{values}\n",
      "checksum #{checksum}\n"
    ])
  end

  defp run(0, _state, _hot, _cold, cache, hits, misses, values), do: {cache, hits, misses, values}

  defp run(n, state, hot, cold, cache, hits, misses, values) do
    state = rem(state * @lehmer_a, @lehmer_m)
    key = pick_key(state, hot, cold)

    case get(cache, key) do
      {:ok, value, cache} ->
        run(n - 1, state, hot, cold, cache, hits + 1, misses, rem(values + value, @modulus))

      :miss ->
        run(n - 1, state, hot, cold, insert(cache, key, key * 2 + 1), hits, misses + 1, values)
    end
  end

  defp pick_key(state, hot, cold) do
    draw = div(state, 100)

    if rem(state, 100) < @hot_percent do
      rem(draw, hot)
    else
      hot + rem(draw, cold)
    end
  end

  # A hit returns the value and makes the key the most recent.
  defp get(%Lru{entries: entries, by_tick: by_tick, clock: clock} = cache, key) do
    case entries do
      %{^key => {value, old}} ->
        by_tick = :gb_trees.insert(clock, key, :gb_trees.delete(old, by_tick))

        {:ok, value,
         %{
           cache
           | entries: %{entries | key => {value, clock}},
             by_tick: by_tick,
             clock: clock + 1
         }}

      %{} ->
        :miss
    end
  end

  # Inserts a key that is not present, evicting the least recent entry when full.
  defp insert(
         %Lru{capacity: capacity, entries: entries, by_tick: by_tick, clock: clock} = cache,
         key,
         value
       ) do
    {entries, by_tick} =
      if map_size(entries) == capacity do
        {_tick, oldest, by_tick} = :gb_trees.take_smallest(by_tick)
        {Map.delete(entries, oldest), by_tick}
      else
        {entries, by_tick}
      end

    %{
      cache
      | entries: Map.put(entries, key, {value, clock}),
        by_tick: :gb_trees.insert(clock, key, by_tick),
        clock: clock + 1
    }
  end

  defp checksum(:none, _position, sum), do: sum

  defp checksum({_tick, key, iter}, position, sum) do
    checksum(:gb_trees.next(iter), position + 1, rem(sum + position * key, @modulus))
  end
end
