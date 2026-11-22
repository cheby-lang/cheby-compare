- **Cheby runs in 2.07 s as an executable and 2.13 s under `cheby run`, about 6× Rust.** The rows
  are 13th and 14th of 21. Rust takes 350 ms and Zig, the fastest, 317 ms. Cheby is ahead of Ruby
  (2.24 s), OCaml (2.44 s), Clojure (2.80 s), Koka (4.57 s) and all three BEAM languages (Erlang
  5.33 s, Elixir 5.46 s, Gleam 6.21 s). TypeScript (1.91 s), Scala (1.61 s) and Python (1.37 s) are
  ahead of it. The October JIT took 3.58 s, 16th of 20. Peak RSS is 230 MB for the executable and
  246 MB for `cheby run`: well under the BEAM rows (1.8 GB to 2.8 GB), but well over Rust's 97.7 MB.
- **The counts live in a persistent hash trie, by design.** `Map` is a HAMT (D-039), and Cheby has
  no mutable hash table (D-017). `map::upsert` changes a map in place when nothing else holds it
  (§9.3, `crates/cheby_runtime/src/hamt/kernels.rs`), so no path is copied: the runtime counters
  report 12.0 million map updates in place and none copied. Each word still pays for a hash, a walk
  down the trie nodes and a call back into the `bump` closure. A word already seen also costs a
  newly allocated `Some` for its old count. The hash function is not the gap: it is SipHash-1-3, the
  same as Rust's default `HashMap`.
- **The call back into `bump` is the largest single cost.** In a profile of the executable, the
  runtime function that calls a closure (`callback::call_in`) takes 18% of the samples, more than
  any other function. The trie code takes 25% in all, allocation and counting 14%, and the text
  kernels 9%. The trie no longer allocates per call: `Path::walk` in
  `crates/cheby_runtime/src/hamt/ops.rs` used to build two `Vec`s for every `upsert`, and it keeps
  its path on the stack now.
- **Splitting copies most of the text twice.** The program splits on `"\n"` and then on `" "`, as
  the SPEC says. `string::split` builds a `List` of freshly allocated strings (`text/kernels.rs`),
  so a byte is copied into a line and then into a word; only a line without a space is reused as it
  is. `std::string` has gained `string::words` since the program was written, which would save the
  copy into lines. The program does not use it yet. Each word would still be a fresh string, because
  the runtime has no substring views. Rust, Go, Zig and C++ key their maps by slices of the file
  buffer. Both costs are current std and runtime choices, not limits of the language.
- **The final sort is a merge sort written in Cheby.** `list::sort_with` (`std/list.cheby`) is a
  bottom-up merge sort over persistent lists. Each comparison is an indirect call to `by_frequency`,
  which takes both tuples apart. The Rust and C++ rows sort an array in place. Combinators such as
  this sort are Cheby code by decision (D-274), so their speed depends on the compiler's output, not
  on a Rust kernel.
- **The rows differ in their splitters, and Cheby's program is long.** Java and Scala split with a
  regex and C# on a char array (see the SPEC), and Koka counts in a red-black tree that the program
  writes itself. Cheby's 49 lines are the third most, after Koka (79) and Gleam (62), partly because
  each std module needs its own import (7 lines) and the fold callbacks are separate functions.
- **Swift's 1.0 GB peak RSS comes from its splitter.** `split(whereSeparator:)` builds the whole
  array of word slices before counting (see its `impl.toml`). The rows that count while they split
  (Rust, Zig, C++) stay near 100 MB.
