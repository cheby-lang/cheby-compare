# json_roundtrip

Parse a JSON document into records, aggregate and transform them, and serialize the result.

## Purpose

It stresses a JSON library end to end: tokenizing text, building strings, numbers, lists and
records, walking them, building a new document and writing it back as compact text. The input is
an array of 50 000 small records with nested objects and arrays, 15 MB of text.

- Languages with a fast, typed JSON library (Rust with `serde_json`, C++, Go, Zig, Java with
  Jackson, C#) parse at hundreds of MB/s and should finish in well under a second.
- Python's and Ruby's JSON parsers are written in C, so they do better than their interpreters
  usually do. The checksum loop over the output bytes is pure interpreter work, so it runs over
  one repetition's output only. Hashing every repetition made the byte loop about 80% of
  Python's time and turned the benchmark into a byte-loop one for the interpreters.
- For Cheby this is expected to be a **weakness**. `std::json` is written in Cheby itself: the
  parser walks the text as a persistent list of code points, decoders are chains of closures, and
  `json::to_string` builds the text in Cheby code. There is no native fast path. It probes the
  cost of persistent data structures and closure calls in a hot, allocation-heavy loop.
- Measured while writing this spec, at the bench size on a busy machine: Rust 0.5 s, Python
  4.5 s, Cheby 65 s wall (53 s user, 320 MB peak RSS), which leaves Cheby well inside the 120 s
  timeout. About 80% of Cheby's time is `json::parse` (about 3 MB/s), most of it the syntax pass.
- Cheby's split into compile and run time is an estimate, as for every benchmark. Its zero-size
  run takes about 25 ms and `cheby check` about 15 ms, so whatever compile work the subtraction
  misses is negligible against a run of about a minute.

## Arguments

Two arguments:

1. `path`: the input file, one of `inputs/data/json-*.json`.
2. `reps`: the number of round trips, a non-negative integer.

## Data

The input files come from `inputs/gen_json.py`. Implementations only read them. The generator is
described here so that the data is understood, not so that it is reimplemented.

Each file is one JSON array of records. Each record has these keys, in this order:

| Key       | JSON type        | Values                                                        |
| --------- | ---------------- | ------------------------------------------------------------- |
| `id`      | integer          | 1, 2, 3, ... in file order                                    |
| `name`    | string           | two words of 3 to 10 letters `a`-`z`, joined by one space     |
| `active`  | `true` / `false` | `true` for about 3 in 4 records                               |
| `score`   | integer          | -1000 to 1000                                                 |
| `tags`    | array of strings | 0 to 4 tags from 16 Greek letter names, repeats possible      |
| `address` | object           | `street` (string), `city` (string), `zip` (integer), in order |
| `history` | array of objects | 0 to 8 objects `{"day": 1..365, "amount": 0..9999}`, in order |

- Every number is an integer and fits in a signed 32-bit integer. There are no floats.
- Every string holds only `a`-`z`, `0`-`9` and spaces, so no string needs an escape. Every JSON
  library writes them the same way.
- The file is ASCII. It has one record per line, `[` and `]` on lines of their own, a space after
  every `:` and `,`, and a final `\n`. An empty array is written `[]\n`.

The generator uses one 64-bit LCG with wrapping arithmetic:

```text
state = 7
next31(): state = (state * 6364136223846793005 + 1442695040888963407) mod 2^64
          return state >> 33
word():   length = 3 + next31() % 8; then length letters, each "abcdefghijklmnopqrstuvwxyz"[next31() % 26]
TAGS = alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi

record i (from 0), with the calls in exactly this order:
  id = i + 1
  name = word() + " " + word()
  active = next31() % 4 != 0
  score = next31() % 2001 - 1000
  tags = next31() % 5 tags, each TAGS[next31() % 16]
  street = str(1 + next31() % 9999) + " " + word() + " street"
  city = word()
  zip = 10000 + next31() % 90000
  history = next31() % 9 entries, each: day = 1 + next31() % 365, then amount = next31() % 10000
```

## Algorithm

```text
FNV_OFFSET = 2166136261
FNV_PRIME = 16777619

main(path, reps):
  text = read the whole file, once
  records_n = active_n = score_sum = tags_n = history_n = amount_sum = output_bytes = 0   # 64-bit
  h = FNV_OFFSET
  repeat reps times, rep = 0, 1, ..., reps - 1:
    records = parse(text)                    # a fresh, complete list of records every time
    kept = []
    for r in records, in order:
      total = sum of e.amount for e in r.history
      records_n += 1
      score_sum += r.score
      tags_n += length(r.tags)
      history_n += length(r.history)
      amount_sum += total
      if r.active:
        active_n += 1
        kept.append({
          "id": r.id,
          "name": r.name,
          "score": r.score + 100 * length(r.tags),
          "tags": r.tags,
          "address": r.address,              # street, city, zip, unchanged
          "history": r.history,              # day, amount per entry, unchanged
          "total": total,
        })
    out = serialize(kept)                    # compact JSON, the bytes of one string
    output_bytes += length of out in bytes
    if rep == reps - 1:                      # the last repetition only
      for b in out: h = ((h xor b) * FNV_PRIME) mod 2^32
  print the eight output lines
```

Rules:

- Read the file once, before the loop. Parse the whole text again in every repetition. Never
  reuse parsed records, kept records or output text from an earlier repetition.
- `parse` must build the complete list of records before any of them is aggregated. No streaming
  or event-based parsing, no lazy parsing, no skipping of fields.
- `serialize` must build the complete output text (a string or byte buffer) before it is hashed.
  Do not hash while writing, and do not write to a sink that hashes.
- Use the JSON library for both directions (see "Libraries" below). Do not hand-write a parser or
  serializer, except Koka, which has no JSON library, and except where a library cannot keep the
  key order (see the guidance).
- The hash `h` is FNV-1a 32-bit over the output of the last repetition only. Every repetition
  writes byte-identical output, so hashing more copies checks nothing more, and in interpreters
  the byte loop would outweigh the JSON work. Every repetition still serializes in full and adds
  its length to `output_bytes`. With `reps` 0, `h` stays `FNV_OFFSET`.
- `h < 2^32` and `FNV_PRIME < 2^25`, so `(h xor b) * FNV_PRIME < 2^57` fits in a signed 64-bit
  integer before the `mod 2^32` (a mask with `0xFFFFFFFF`). Unsigned 32-bit wrapping
  multiplication gives the same result.
- Use 64-bit integers for the counters. `amount_sum` exceeds 2^32 at the bench size.
- Single-threaded.

### The output document

This is the start of the output for `json-test.json` (the first record of every input file is
the same). `serialize(kept)` is compact JSON with no whitespace at all, keys in exactly this order:

```text
[{"id":1,"name":"fxhtzgify pwerkd","score":927,"tags":["iota"],"address":{"street":"1655 sfigrjayh street","city":"dftnrewzf","zip":56288},"history":[{"day":31,"amount":1544},{"day":310,"amount":4304},{"day":122,"amount":8490},{"day":343,"amount":6654},{"day":318,"amount":4668}],"total":25660},...]
```

- Records are separated by `,`. No records gives `[]`. Empty `tags` or `history` give `[]`.
- `active` is not written. `score` is the changed value. `total` is the last key.
- Integers are plain decimal with a leading `-` when negative.
- Strings are written between `"` with nothing escaped, because none of their characters needs it.
- The output is ASCII, so its length in bytes equals its length in characters.

## Output

Exactly these eight lines, each ending in `\n`:

```text
records <records_n>
active <active_n>
score_sum <score_sum>
tags <tags_n>
history <history_n>
amount_sum <amount_sum>
output_bytes <output_bytes>
output_fnv1a <h>
```

`h` is printed as an unsigned decimal number. For the test size (`json-test.json`, 2 repetitions):

```text
records 2000
active 1524
score_sum 268
tags 3898
history 8084
amount_sum 40704562
output_bytes 415206
output_fnv1a 662159601
```

## Size 0

`json-0.json` is the empty array `[]`, run once. The program reads, parses, transforms, serializes
`[]` and hashes it, through the same code as every other size.

```text
records 0
active 0
score_sum 0
tags 0
history 0
amount_sum 0
output_bytes 2
output_fnv1a 1947613349
```

## Sizes

| Size    | Arguments                  | Notes                                                    |
| ------- | -------------------------- | -------------------------------------------------------- |
| `zero`  | `{data}/json-0.json 1`     | the empty array                                          |
| `test`  | `{data}/json-test.json 2`  | 1 000 records, 307 KB, two repetitions                   |
| `bench` | `{data}/json-bench.json 9` | 50 000 records, 15.4 MB, 9 repetitions; Rust about 0.5 s |

## Libraries

Standard-library JSON where it exists, else the library named in CONVENTIONS.md. Name it in
`impl.toml` under `libs`.

## Per-language guidance

Typed decoding into records or structs is recommended. The fixed field order then makes the
output canonical. A dynamic value tree is allowed when it keeps the key order of the input and of
the output record. Whatever the representation, `kept` is built from new output records.
`address` and `history` may be shared with the parsed records only when their representation
keeps the key order `street`, `city`, `zip` and `day`, `amount`. A plain hash map does not.

- **Rust**: `serde` with `#[derive(Deserialize, Serialize)]` and `serde_json::from_str` /
  `serde_json::to_vec`. The output struct may borrow from the parsed record.
- **C++**: `nlohmann::ordered_json`, **not** `nlohmann::json`, whose `std::map` sorts the keys.
  Or typed structs with `NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE` and an `ordered_json`. `dump()`
  with no indent is compact.
- **Go**: `encoding/json` with structs. Struct fields are written in declaration order. Start
  with `kept := make([]Output, 0)` (or `[]Output{}`): a nil slice marshals as `null`, which
  gives the wrong output at size 0.
- **Zig**: `std.json.parseFromSlice` into structs and `std.json.stringify` (or its current name)
  with default options, which are compact.
- **Odin**: `core:encoding/json` `unmarshal` into structs and `marshal` with default options.
  Check that the output is compact.
- **Swift**: `Codable` with `JSONDecoder` and `JSONEncoder`. Check that the encoder writes keys in
  the order `encode(to:)` encodes them. If it does not, write the output with a small hand-written
  serializer and say so in `impl.toml` `notes`.
- **Java**: Jackson `ObjectMapper` with records, which are written in component order (or
  `@JsonPropertyOrder`).
- **Scala**: `upickle` macro readers and writers, or `ujson` values (`ujson.Obj` keeps insertion
  order). `ujson.write` / `upickle.default.write` with no indent.
- **C#**: `System.Text.Json` with records or classes. Properties are written in declaration order.
  Property names are used as written (PascalCase) and matched case-sensitively, so pass
  `new JsonSerializerOptions(JsonSerializerDefaults.Web)` (camelCase, case-insensitive) or put
  `[JsonPropertyName("...")]` on each property. Otherwise the lowercase keys decode to defaults.
- **TypeScript**: `JSON.parse` and `JSON.stringify`, with interfaces for the records. Object keys
  keep insertion order. Build the output object literal in the key order above. FNV-1a:
  `h = Math.imul(h ^ b, 16777619) >>> 0`. Get the bytes with `Buffer.from(out)` or count `out.length`.
- **Python**: `json.loads` and `json.dumps(kept, separators=(",", ":"))`. Dicts keep order.
- **Ruby**: `JSON.parse` and `JSON.generate` (compact by default). Hashes keep order.
- **Nim**: `std/json` (`parseJson`, `to` or `jsonTo` into objects, `%` / `%*` and `$` for
  compact output). `JsonNode` objects keep insertion order.
- **OCaml**: `yojson`. `` `Assoc `` lists keep their order, `Yojson.Safe.to_string` is compact.
  Ints may be `` `Int ``; the values fit.
- **Erlang**: OTP's `json` module. `json:decode/1` gives maps, which do not keep key order, so
  write the output records in order with `json:encode/2` and a custom encoder that uses
  `json:encode_key_value_list/2` for each record (or build key-value lists). The same holds for
  `address` and every `history` entry: `json:decode/1` returns them as maps too, which would
  encode in sorted key order (`city`, `street`, `zip` and `amount`, `day`). Write them as ordered
  key-value lists as well. Loops become
  `lists:foldl` or tail recursion carrying the counters.
- **Elixir**: the built-in `JSON` module (Elixir 1.18+). Maps do not keep key order, so encode
  output records as structs with a `JSON.Encoder` implementation that writes keys in order, or
  with `:json.encode/2` as in Erlang. `address` and every `history` entry come back from
  `JSON.decode` as maps too, so write them as ordered key-value lists
  (`:json.encode_key_value_list/2`) or as structs with an ordered encoder as well. Use
  `Enum.reduce` for the loops and `:binary.bin_to_list` or
  a binary comprehension for the hash.
- **Gleam**: `gleam_json` with `gleam/dynamic/decode` decoders into custom types, and
  `json.object([...])` (which keeps order) plus `json.to_string`. Recursion or `list.fold`.
- **Clojure**: `clojure.data.json` `read-str` (with `:key-fn keyword`) and `write-str`. Hash maps
  do not keep order, so build each output record as an `array-map` (or `(array-map :id ...)`) in
  the key order above, or as a `defrecord`. Address and history maps come from the parser, so
  rebuild them as array-maps too if their order is not kept. Use `reduce` for the loops.
- **Koka**: a hand-written recursive-descent parser over the input string into a `value` type
  (or straight into records), and a serializer that builds the output with a string builder or a
  list of strings joined once. Keep it close to what a library would do.
- **Cheby**: `json::parse(text, decode::list(record_decoder()))` with `decode::field` decoders,
  output records built as `json::Object([...])` and written with `json::to_string`. Count
  `bytes::length(bytes::from_string(output))` and, in the last repetition, hash with
  `bytes::fold` over the same bytes. Counters in a record type folded with `list::fold`,
  repetitions as a recursive function.
