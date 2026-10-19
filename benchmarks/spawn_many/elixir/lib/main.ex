defmodule Main do
  @moduledoc "Spawns n short tasks in batches of 1000, joins each batch, prints the sum of their results."

  @batch 1000
  @rounds 10
  @modulus 2_147_483_647
  @multiplier 48271

  def main do
    # `erl -eval` runs main in a process that traps exits. Restore the default, so that each
    # linked task's normal exit is not left in the mailbox as an {:EXIT, pid, :normal} message,
    # which would make every later receive scan a growing backlog.
    Process.flag(:trap_exit, false)
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()
    sum = batches(0, n, 0)
    IO.write(["tasks: ", Integer.to_string(n), "\nsum: ", Integer.to_string(sum), ?\n])
  end

  # The value of the task with this index: @rounds MINSTD steps from index + 1.
  defp work(index), do: steps(@rounds, index + 1)

  defp steps(0, x), do: x
  defp steps(k, x), do: steps(k - 1, rem(x * @multiplier, @modulus))

  defp batches(start, n, sum) when start >= n, do: sum

  defp batches(start, n, sum) do
    batch = spawn_and_join(start, min(@batch, n - start))
    batches(start + @batch, n, sum + batch)
  end

  # One task per index in start..start + count - 1, all spawned before the first join.
  defp spawn_and_join(start, count) do
    start..(start + count - 1)//1
    |> Enum.map(fn i -> Task.async(fn -> work(i) end) end)
    |> Task.await_many(:infinity)
    |> Enum.sum()
  end
end
