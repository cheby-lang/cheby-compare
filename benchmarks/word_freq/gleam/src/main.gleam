//// word_freq: counts the words of a file and prints the 20 most frequent.

import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/string

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

// Erlang returns {ok, Bin} | {error, Reason}, which is how Gleam represents a Result.
@external(erlang, "file", "read_file")
fn read_file(path: String) -> Result(String, reason)

// The options of binary:split/3; they compile to the atoms `global` and `trim_all`.
type SplitOption {
  Global
  TrimAll
}

// binary:split(Text, [<<" ">>, <<"\n">>], [global, trim_all]), as in the SPEC's Gleam guidance:
// gleam/string.split is grapheme-aware and far slower.
@external(erlang, "binary", "split")
fn binary_split(
  subject: String,
  patterns: List(String),
  options: List(SplitOption),
) -> List(String)

const top = 20

pub fn main() -> Nil {
  let assert [path, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(text) = read_file(path)
  let words = binary_split(text, [" ", "\n"], [Global, TrimAll])
  let counts =
    list.fold(words, dict.new(), fn(acc, word) {
      dict.upsert(acc, word, fn(count) {
        case count {
          Some(c) -> c + 1
          None -> 1
        }
      })
    })
  let ranked =
    counts
    |> dict.to_list
    |> list.sort(fn(a, b) {
      let #(word_a, count_a) = a
      let #(word_b, count_b) = b
      int.compare(count_b, count_a)
      |> order.lazy_break_tie(fn() { string.compare(word_a, word_b) })
    })
  let lines =
    ranked
    |> list.take(top)
    |> list.map(fn(entry) {
      let #(word, count) = entry
      int.to_string(count) <> " " <> word <> "\n"
    })
  io.print(
    string.concat([
      "total " <> int.to_string(list.length(words)) <> "\n",
      "distinct " <> int.to_string(dict.size(counts)) <> "\n",
      ..lines
    ]),
  )
}
