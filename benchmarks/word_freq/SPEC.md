# word_freq

Word frequency: read a text file, split it into words, count them in a hash map, and print the
most frequent ones.

## Purpose

It stresses reading a large file, cutting it into many small strings, hashing those strings, and
updating a hash map about 12 million times. A full sort of about 200 thousand entries comes last.

- Languages with a mutable hash table and string slices that point into the file buffer (Rust, Go,
  Zig, C++) should be fastest. Most of their time is hashing and probing.
- Tracing-GC languages pay for one allocation per word, but these die young.
- The BEAM languages (Erlang, Elixir, Gleam) use persistent maps and copy a path on every update.
  Clojure avoids the copies: `frequencies` counts through a transient map. Scala uses
  `mutable.HashMap` and belongs with the hash-table languages.
- Koka 3.2's standard library has no map, hash or sort, so its row measures a red-black tree and a
  merge sort written in the program (see the Koka guidance).
- For Cheby this is a probe of its persistent hash map (a HAMT, D-039), which `map::upsert` updates
  in place when the map is unique (§9.3), and of `string::split`, which builds an RRB-vector `List`
  of fresh strings. Cheby has no whitespace splitter, so it splits on `"\n"` and then on `" "`.
  Expect Cheby behind the hash-table languages and near the BEAM languages. It is a weakness more
  than a strength.

## Arguments

One argument: the path of a text file. The program reads that file and nothing else.

## Data

The runner generates the files with `inputs/gen_word_freq.py` into `inputs/data/`. Programs only
read them. The generator is described here so that the files can be checked.

The file is ASCII. Its only bytes are `a`-`z`, space (0x20) and newline (0x0A). Within a line,
words are separated by exactly one space. Every line ends in `\n`. Some lines are empty. There is
no leading or trailing space on a line. An empty file is valid.

The generator uses one 64-bit LCG, with wrapping arithmetic, seeded with 42 for each file:

```text
state = 42
next():                               # 31 bits
  state = (state * 6364136223846793005 + 1442695040888963407) mod 2^64
  return state >> 33

BUCKETS = 18
V = 2^BUCKETS - 1                     # 262143 vocabulary entries

vocab = []
repeat V times:                       # the vocabulary comes first
  len = 2 + next() % 9                # 2..10 letters
  word = len letters, each "abcdefghijklmnopqrstuvwxyz"[next() % 26], in order
  vocab.append(word)                  # duplicates are allowed

remaining = N                         # the number of words in the file
while remaining > 0:
  k = min(1 + next() % 16, remaining) # 1..16 words on this line
  line = []
  repeat k times:
    b = next() % BUCKETS              # a bucket, uniformly
    i = (2^b - 1) + next() % 2^b      # a word within bucket b, uniformly
    line.append(vocab[i])
  write join(line, " ") + "\n"
  if next() % 8 == 0: write "\n"      # an empty line
  remaining = remaining - k
```

Bucket `b` holds `2^b` words and gets `1/18` of the draws, so a word's frequency falls roughly as
`1/rank`, a Zipf-like skew. Because vocabulary entries can repeat, the distinct count is lower
than `V`.

## Algorithm

```text
main(path):
  text = read the whole file             # one read, as a string or as bytes
  counts = new hash map: word -> int
  total = 0
  for each word in split_whitespace(text):   # maximal runs of non-space, non-newline bytes
    counts[word] = counts[word] + 1      # 1 when absent
    total = total + 1
  entries = list of (word, count) from counts
  sort entries by count descending, then by word ascending (byte order)
  print "total {total}"
  print "distinct {size of counts}"
  for the first min(20, size of entries) entries:
    print "{count} {word}"
```

Rules:

- **Read the whole file** into memory first, then split it. No line-by-line or streamed reading,
  no memory mapping.
- **Splitting.** A word is a maximal run of bytes that are neither space nor newline. Empty words
  do not exist. Use the standard library's whitespace splitter where it has one (`str.split()`,
  `split_ascii_whitespace`, `strings.Fields`, `tokenizeAny`). Where it has none, split on `"\n"`
  and then on `" "` and skip empty parts, or scan the bytes in a simple loop (C++). Building a list
  of all words first and then counting is allowed; so is counting while splitting.
- **Counting** uses the standard library's hash map with its default hash function. No custom
  hashers, no capacity hints, no tries, no perfect hashing, no interning tables. A word key may be
  a slice that points into the file buffer or a copied string, whichever is normal in the
  language. Functional languages use their standard map (see below) and update it one word at a
  time, or use a standard counting function such as `Counter`, `frequencies` or `Enum.frequencies`
  that does the same. Koka is the exception: see its guidance.
- **`total`** is the number of words. It may be counted while splitting or summed over the map.
- **Sorting.** Sort all distinct entries with the standard library's sort and a comparator or key
  (Koka, which has none, is the exception: see its guidance). No partial sort, heap, `most_common`
  or top-k selection. Words compare by ordinal or byte comparison: `<` or the default string
  comparison where the language has an ordinal one, `string.CompareOrdinal` or
  `StringComparer.Ordinal` in C#, and never a locale-aware compare such as `localeCompare` or a
  culture comparer. For this ASCII input, byte order is the same as code-point order.
- Single-threaded.

## Output

Exactly these lines, each ending in `\n`. Integers print in plain decimal.

```text
total <total>
distinct <distinct>
<count> <word>          up to 20 lines, by count descending, then word ascending
```

For the test file (`words-test.txt`, 20000 words) the output starts:

```text
total 20000
distinct 8389
1121 gqv
602 cigy
591 qzgw
303 gtqgpctmq
```

The full outputs are in `expected/`.

## Size 0

`words-0.txt` is an empty file. The program still reads it, splits it, builds an empty map, sorts
an empty list and prints two lines. Splitting `""` on `"\n"` gives one empty part in most
languages; it holds no word.

```text
total 0
distinct 0
```

## Sizes

| Size    | File              | Words      | Bytes      | Notes                                      |
| ------- | ----------------- | ---------- | ---------- | ------------------------------------------ |
| `zero`  | `words-0.txt`     | 0          | 0          | empty file, two lines of output            |
| `test`  | `words-test.txt`  | 20 000     | 136 695    | 8 389 distinct words                       |
| `bench` | `words-bench.txt` | 12 000 000 | 81 994 366 | 217 206 distinct words; Rust about 0.6 s   |

SHA-256 of the generated files:

```text
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  words-0.txt
55808bda2784174353df478b33c63932b50a2b98c7cfc4edac6c8cd8120dfa96  words-test.txt
4abc37441fc163349741d69ab78e1aa117526a692236d09a9fee99545cd3cde2  words-bench.txt
```

## Per-language guidance

- **Rust**: `fs::read_to_string`, `split_ascii_whitespace`, `HashMap<&str, u64>` from `std` with
  the default hasher and the `entry` API, `Vec::sort_by`.
- **Go**: `os.ReadFile`, `strings.Fields(string(data))` (or `bytes.Fields`), `map[string]int`,
  `sort.Slice` or `slices.SortFunc`.
- **Zig**: read the file with the standard allocator, `std.mem.tokenizeAny(u8, text, " \n")`,
  `std.StringHashMap(u64)`, `std.mem.sort` (or `std.sort.pdq`).
- **Odin**: `os.read_entire_file`, `strings.fields` or a split on `"\n"` and `" "`,
  `map[string]int`, `slice.sort_by`.
- **C++**: read into a `std::string`, scan the bytes in a loop, `std::unordered_map<std::string_view,
  long>`, `std::sort`. No third-party hash maps.
- **Swift**: read as `Data` or `String`, split the UTF-8 bytes (`split(whereSeparator:)`) or the
  string, `[Substring: Int]` or `[String: Int]`, `sorted(by:)`.
- **Nim**: `readFile`, `splitWhitespace`, `Table[string, int]` or `CountTable` (sort its pairs
  with `algorithm.sort`, not `sort(CountTable)`'s own order).
- **Java, Scala, C#**: read the file as one string, split it (`split("\\s+")` after skipping a
  leading empty part, or a simple index loop), then sort a list of entries with a comparator. In
  C#, `text.Split([' ', '\n'], StringSplitOptions.RemoveEmptyEntries)` is allowed too.
  The Java and Scala rows split with the regex and the C# row with the char array, so part of any
  gap between them is the splitter: the regex builds the whole array first and costs more CPU.
  - Java: `HashMap<String, Integer>` with `merge`; compare words with `String.compareTo`, which is
    ordinal.
  - Scala: `scala.collection.mutable.HashMap[String, Int]` updated with `updateWith` or with
    `getOrElse` and `update`, not an immutable `Map`, so that Scala measures a standard hash table.
    Compare words with `<` or `compareTo`, which are ordinal. Say so in `impl.toml` `notes`.
  - C#: `Dictionary<string, int>` with its default comparer, which is already ordinal. Compare
    words with `string.CompareOrdinal` (or sort with `StringComparer.Ordinal`). `CompareTo`,
    `Comparer<string>.Default` and `OrderBy(...).ThenBy(e => e.Key)` without a comparer use the
    current culture: they are slower (about 235 ms against 91 ms for this sort) and change the order
    under tailored locales.
- **TypeScript**: `fs.readFileSync(path, "latin1")` or `"utf8"`, `text.split(/\s+/)` without empty
  parts, `Map<string, number>`, `Array.prototype.sort` with a comparator that compares words with
  `<`, not `localeCompare`.
- **Python**: `str.split()`, `collections.Counter` or a `dict`, `sorted` with
  `key=lambda e: (-e[1], e[0])`.
- **Ruby**: `File.read`, `split`, `Hash.new(0)` or `tally`, `sort_by { |w, c| [-c, w] }`.
- **OCaml**: `In_channel.with_open_bin` and `input_all`, `String.split_on_char` on `'\n'` and
  then `' '` (skip `""`), `Hashtbl`, `List.sort` (or `Array.sort`) with a comparator.
- **Erlang**: `file:read_file`, `binary:split(Bin, [<<" ">>, <<"\n">>], [global, trim_all])`, a
  `maps` map with `maps:update_with/4`, `lists:sort/2`.
- **Elixir**: `File.read!`, `String.split/1`, `Enum.frequencies/1` or `Map.update/4`,
  `Enum.sort_by(&{-elem(&1, 1), elem(&1, 0)})` or `Enum.sort/2`.
- **Gleam**: `simplifile` is a third-party package, so read the file through an `@external` to
  `file:read_file/1`. Split through an `@external(erlang, "binary", "split")` called as
  `binary:split(Bin, [<<" ">>, <<"\n">>], [global, trim_all])`, the same call as Erlang, then count
  in a `gleam/dict` with `dict.upsert` and sort with `list.sort` and a comparator. Do not use
  `gleam/string.split`: in gleam_stdlib 1.0 it goes through Erlang's grapheme-aware
  `string:split/3`, which took about 30 s at bench size against about 1.2 s for `binary:split`, so
  the row would measure grapheme segmentation, not this benchmark. The external is justified the
  same way as the `file:read_file` one. Name both externals in `impl.toml` `notes`.
- **Clojure**: `slurp`, `clojure.string/split` on `#"\s+"` (drop a leading `""`), `frequencies`
  or `reduce` over a transient hash map, `sort-by` with a comparator.
- **Koka**: read the file through `std/os/file`, split with `split` on `"\n"` and `" "` and skip
  empty parts. Koka 3.2's standard library has no map (`std/data/map`, `dict`, `imap` and `set` are
  empty stubs), no string hash and no sort, so the program writes two small structures itself:
  - a persistent red-black tree keyed by `string`, ordered by the standard `<` and `cmp` on
    strings, in the FBIP style of Koka's own `samples/basic/rbtree-fbip.kk` (or the plainer
    `rbtree.kk`); no hash table and no association list;
  - a top-down merge sort on `list` with the same comparator as the other languages.

  Name both in `impl.toml` `notes`. Koka's `cmp` on strings compares UTF-8 bytes, which is the
  byte order the output needs.
- **Cheby**: `io::read_file`, `string::split` on `"\n"` and then on `" "` with empty parts skipped,
  a `list::fold` over the lines and the words that threads a `Map<String, Int>` through
  `map::upsert`, then `map::to_list`, `list::sort_with` and `list::take`.
