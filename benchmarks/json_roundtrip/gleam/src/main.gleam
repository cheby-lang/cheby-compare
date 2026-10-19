//// json_roundtrip: parses a JSON array of records, transforms it and serializes it again.

import gleam/bit_array
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/string

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

// Erlang returns {ok, Bin} | {error, Reason}, which is how Gleam represents a Result.
@external(erlang, "file", "read_file")
fn read_file(path: String) -> Result(BitArray, reason)

const fnv_offset = 2_166_136_261

const fnv_prime = 16_777_619

type Address {
  Address(street: String, city: String, zip: Int)
}

type Entry {
  Entry(day: Int, amount: Int)
}

type Record {
  Record(
    id: Int,
    name: String,
    active: Bool,
    score: Int,
    tags: List(String),
    address: Address,
    history: List(Entry),
  )
}

type Output {
  Output(
    id: Int,
    name: String,
    score: Int,
    tags: List(String),
    address: Address,
    history: List(Entry),
    total: Int,
  )
}

type Stats {
  Stats(
    records: Int,
    active: Int,
    score_sum: Int,
    tags: Int,
    history: Int,
    amount_sum: Int,
    output_bytes: Int,
    hash: Int,
  )
}

pub fn main() -> Nil {
  let assert [path, reps_arg, ..] =
    list.map(plain_arguments(), charlist_to_string)
  let assert Ok(reps) = int.parse(reps_arg)
  let assert Ok(text) = read_file(path)
  let s = repeat(text, 0, reps, Stats(0, 0, 0, 0, 0, 0, 0, fnv_offset))
  io.print(
    string.concat([
      line("records", s.records),
      line("active", s.active),
      line("score_sum", s.score_sum),
      line("tags", s.tags),
      line("history", s.history),
      line("amount_sum", s.amount_sum),
      line("output_bytes", s.output_bytes),
      line("output_fnv1a", s.hash),
    ]),
  )
}

fn line(name: String, value: Int) -> String {
  name <> " " <> int.to_string(value) <> "\n"
}

fn repeat(text: BitArray, rep: Int, reps: Int, s: Stats) -> Stats {
  case rep == reps {
    True -> s
    False -> {
      let assert Ok(records) =
        json.parse_bits(text, decode.list(record_decoder()))
      let #(s, kept_rev) = list.fold(records, #(s, []), visit)
      let out =
        kept_rev
        |> list.reverse
        |> json.array(encode_output)
        |> json.to_string
      let s = Stats(..s, output_bytes: s.output_bytes + string.byte_size(out))
      let s = case rep == reps - 1 {
        True -> Stats(..s, hash: fnv1a(fnv_offset, bit_array.from_string(out)))
        False -> s
      }
      repeat(text, rep + 1, reps, s)
    }
  }
}

fn visit(acc: #(Stats, List(Output)), r: Record) -> #(Stats, List(Output)) {
  let #(s, kept) = acc
  let total = list.fold(r.history, 0, fn(sum, e) { sum + e.amount })
  let n_tags = list.length(r.tags)
  let s =
    Stats(
      ..s,
      records: s.records + 1,
      score_sum: s.score_sum + r.score,
      tags: s.tags + n_tags,
      history: s.history + list.length(r.history),
      amount_sum: s.amount_sum + total,
    )
  case r.active {
    True -> {
      let out =
        Output(
          id: r.id,
          name: r.name,
          score: r.score + 100 * n_tags,
          tags: r.tags,
          address: r.address,
          history: r.history,
          total: total,
        )
      #(Stats(..s, active: s.active + 1), [out, ..kept])
    }
    False -> #(s, kept)
  }
}

fn record_decoder() -> Decoder(Record) {
  use id <- decode.field("id", decode.int)
  use name <- decode.field("name", decode.string)
  use active <- decode.field("active", decode.bool)
  use score <- decode.field("score", decode.int)
  use tags <- decode.field("tags", decode.list(decode.string))
  use address <- decode.field("address", address_decoder())
  use history <- decode.field("history", decode.list(entry_decoder()))
  decode.success(Record(id:, name:, active:, score:, tags:, address:, history:))
}

fn address_decoder() -> Decoder(Address) {
  use street <- decode.field("street", decode.string)
  use city <- decode.field("city", decode.string)
  use zip <- decode.field("zip", decode.int)
  decode.success(Address(street:, city:, zip:))
}

fn entry_decoder() -> Decoder(Entry) {
  use day <- decode.field("day", decode.int)
  use amount <- decode.field("amount", decode.int)
  decode.success(Entry(day:, amount:))
}

fn encode_output(o: Output) -> Json {
  json.object([
    #("id", json.int(o.id)),
    #("name", json.string(o.name)),
    #("score", json.int(o.score)),
    #("tags", json.array(o.tags, json.string)),
    #("address", encode_address(o.address)),
    #("history", json.array(o.history, encode_entry)),
    #("total", json.int(o.total)),
  ])
}

fn encode_address(a: Address) -> Json {
  json.object([
    #("street", json.string(a.street)),
    #("city", json.string(a.city)),
    #("zip", json.int(a.zip)),
  ])
}

fn encode_entry(e: Entry) -> Json {
  json.object([#("day", json.int(e.day)), #("amount", json.int(e.amount))])
}

fn fnv1a(h: Int, bytes: BitArray) -> Int {
  case bytes {
    <<b, rest:bytes>> ->
      fnv1a(
        int.bitwise_and(int.bitwise_exclusive_or(h, b) * fnv_prime, 0xFFFFFFFF),
        rest,
      )
    _ -> h
  }
}
