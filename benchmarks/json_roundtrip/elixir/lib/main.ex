defmodule Main do
  @moduledoc "json_roundtrip: parses a JSON array of records, transforms it and serializes it again."

  import Bitwise

  @fnv_offset 2_166_136_261
  @fnv_prime 16_777_619

  defmodule Address do
    @moduledoc "An output address; the derived encoder writes the keys in field order."
    @derive JSON.Encoder
    defstruct [:street, :city, :zip]
  end

  defmodule Entry do
    @moduledoc "An output history entry, keys in field order."
    @derive JSON.Encoder
    defstruct [:day, :amount]
  end

  defmodule Output do
    @moduledoc "An output record, keys in field order."
    @derive JSON.Encoder
    defstruct [:id, :name, :score, :tags, :address, :history, :total]
  end

  defmodule Stats do
    @moduledoc "The running counters."
    defstruct records: 0,
              active: 0,
              score_sum: 0,
              tags: 0,
              history: 0,
              amount_sum: 0,
              output_bytes: 0,
              hash: 2_166_136_261
  end

  def main do
    [path, reps_arg | _] = :init.get_plain_arguments()
    reps = reps_arg |> List.to_string() |> String.to_integer()
    text = File.read!(List.to_string(path))

    s =
      Enum.reduce(0..(reps - 1)//1, %Stats{}, fn rep, acc ->
        round_trip(text, rep, reps, acc)
      end)

    IO.write([
      "records #{s.records}\n",
      "active #{s.active}\n",
      "score_sum #{s.score_sum}\n",
      "tags #{s.tags}\n",
      "history #{s.history}\n",
      "amount_sum #{s.amount_sum}\n",
      "output_bytes #{s.output_bytes}\n",
      "output_fnv1a #{s.hash}\n"
    ])
  end

  defp round_trip(text, rep, reps, s0) do
    records = JSON.decode!(text)
    {s1, kept_rev} = Enum.reduce(records, {s0, []}, &visit/2)
    out = JSON.encode!(Enum.reverse(kept_rev))
    s2 = %{s1 | output_bytes: s1.output_bytes + byte_size(out)}

    if rep == reps - 1 do
      %{s2 | hash: fnv1a(out)}
    else
      s2
    end
  end

  defp visit(
         %{
           "id" => id,
           "name" => name,
           "active" => active,
           "score" => score,
           "tags" => tags,
           "address" => address,
           "history" => history
         },
         {s, kept}
       ) do
    total = Enum.reduce(history, 0, fn %{"amount" => amount}, sum -> sum + amount end)
    n_tags = length(tags)

    s = %{
      s
      | records: s.records + 1,
        score_sum: s.score_sum + score,
        tags: s.tags + n_tags,
        history: s.history + length(history),
        amount_sum: s.amount_sum + total
    }

    if active do
      out = %Output{
        id: id,
        name: name,
        score: score + 100 * n_tags,
        tags: tags,
        address: %Address{street: address["street"], city: address["city"], zip: address["zip"]},
        history: Enum.map(history, fn e -> %Entry{day: e["day"], amount: e["amount"]} end),
        total: total
      }

      {%{s | active: s.active + 1}, [out | kept]}
    else
      {s, kept}
    end
  end

  defp fnv1a(bytes) do
    for <<b <- bytes>>, reduce: @fnv_offset do
      h -> bxor(h, b) * @fnv_prime &&& 0xFFFFFFFF
    end
  end
end
