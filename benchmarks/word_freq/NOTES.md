- **Cheby ranks 16th of 20, about 10× slower than Rust.** Its estimated run is 3.58 s, against
  350 ms for Rust (10.3×) and 317 ms for Zig, the fastest (11.3×). It is ahead of all three BEAM
  languages (Erlang 5.33 s, Elixir 5.46 s, Gleam 6.21 s) and of Koka (4.57 s), and behind OCaml
  (2.44 s, 1.47× faster) and Clojure (2.80 s). Its peak RSS is 257 MB: well under the BEAM rows
  (1.8 GB to 2.8 GB), but well over Rust's 97.7 MB.
- **The counts live in a persistent hash trie, by design.** `Map` is a HAMT (D-039), and Cheby has
  no mutable hash table (D-017). `map::upsert` changes a map in place when nothing else holds it
  (§9.3, `crates/cheby_runtime/src/hamt/kernels.rs`), so no path is copied. Each word still pays
  for a generic structural hash (`generic/hash.rs`), a walk down the trie nodes and a call back
  into the `bump` closure. A word already seen also costs a newly allocated `Some` for its old
  count. The hash function is not the gap: it is SipHash-1-3, the same as Rust's default
  `HashMap`. In a profile on a prefix of the bench file, the upsert path was the largest single
  cost.
- **One per-call cost belongs to the current runtime, not to the design.** `Path::walk` in
  `crates/cheby_runtime/src/hamt/ops.rs` allocates two `Vec`s for every `insert`, `upsert` and
  `remove`, to record the path it walks. Those allocations showed up in the same profile.
- **Splitting copies most of the text twice.** `std::string` has no whitespace splitter, so the
  program splits on `"\n"` and then on `" "`, as the SPEC says. `string::split` builds a `List` of
  freshly allocated strings (`text/kernels.rs`), so a byte is copied into a line and then into a
  word; only a line without a space is reused as it is. A whitespace splitter would save the copy
  into lines. Each word would still be a fresh string, because the runtime has no substring views.
  Rust, Go, Zig and C++ key their maps by slices of the file buffer. Both costs are current std
  and runtime choices, not limits of the language.
- **The final sort is a merge sort written in Cheby.** `list::sort_with` (`std/list.cheby`) is a
  bottom-up merge sort over persistent lists. Each comparison is an indirect call to
  `by_frequency`, which takes both tuples apart. The Rust and C++ rows sort an array in place.
  Combinators such as this sort are Cheby code by decision (D-274), so their speed depends on the
  compiler's output, not on a Rust kernel.
- **The estimate does not distort this row.** The size-0 run that is subtracted takes 13 ms, against
  a whole run of 3.60 s. The rows differ in their splitters: Java and Scala split with a regex
  and C# on a char array (see the SPEC), and Koka counts in a red-black tree that the program
  writes itself. Cheby's 49 lines are the third most, after Koka (79) and Gleam (62), partly because
  each std module needs its own import (7 lines) and the fold callbacks are separate functions.
- **Swift's 1.0 GB peak RSS comes from its splitter.** `split(whereSeparator:)` builds the whole
  array of word slices before counting (see its `impl.toml`). The rows that count while they split
  (Rust, Zig, C++) stay near 100 MB.
