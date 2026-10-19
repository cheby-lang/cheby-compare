defmodule Main do
  @moduledoc "Two processes pass a number back and forth n times; prints n and the sum of the replies."

  def main do
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()
    a = self()
    b = spawn(fn -> echo(n, a) end)
    sum = play(1, n, b, 0)
    IO.write([Integer.to_string(n), ?\n, Integer.to_string(sum), ?\n])
  end

  # Task B: answers each {:ping, x} with {:pong, x + 1}, exactly n times, then ends.
  defp echo(0, _a), do: :ok

  defp echo(n, a) do
    receive do
      {:ping, x} ->
        send(a, {:pong, x + 1})
        echo(n - 1, a)
    end
  end

  # Task A (the main process): sends i = 1..n on ping and adds up the answers from pong.
  defp play(i, n, _b, sum) when i > n, do: sum

  defp play(i, n, b, sum) do
    send(b, {:ping, i})

    receive do
      {:pong, x} -> play(i + 1, n, b, sum + x)
    end
  end
end
