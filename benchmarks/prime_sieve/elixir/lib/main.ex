defmodule Main do
  @moduledoc """
  The concurrent prime sieve: a generator process and one filter process per prime,
  connected by the pull protocol (each stage asks the one before it for every number).
  """

  def main do
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()
    gen = spawn(fn -> generator(2) end)
    {last, sum} = primes(n, gen, self(), 0, 0)
    # The stages stay blocked in receive; the halt(0) after main ends them
    # (SPEC "Shut down", option 1).
    IO.write([
      ["primes: ", Integer.to_string(n), ?\n],
      ["last: ", Integer.to_string(last), ?\n],
      ["sum: ", Integer.to_string(sum), ?\n]
    ])
  end

  # Receives n primes from the end of the pipeline, spawning a filter after each one.
  # `me` is the main process's pid, set up once.
  defp primes(0, _cur, _me, last, sum), do: {last, sum}

  defp primes(k, cur, me, _last, sum) do
    send(cur, {:next, me})

    receive do
      {:num, p} ->
        next = spawn(fn -> filter(p, cur) end)
        primes(k - 1, next, me, p, sum + p)
    end
  end

  # Answers each request with the next integer, from 2 upward.
  defp generator(i) do
    receive do
      {:next, from} ->
        send(from, {:num, i})
        generator(i + 1)
    end
  end

  # Answers each request with the next number from `up` that `prime` does not divide.
  # `me` is this filter's own pid, set up once, so requests upstream carry it.
  defp filter(prime, up), do: filter_loop(prime, up, self())

  defp filter_loop(prime, up, me) do
    receive do
      {:next, from} ->
        send(from, {:num, pull(prime, up, me)})
        filter_loop(prime, up, me)
    end
  end

  defp pull(prime, up, me) do
    send(up, {:next, me})

    receive do
      {:num, m} when rem(m, prime) == 0 -> pull(prime, up, me)
      {:num, m} -> m
    end
  end
end
