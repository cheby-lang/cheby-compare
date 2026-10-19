- **Cheby ties Erlang and Elixir, 47× slower than Rust.** Its estimated run is 31.3 s, 18th of 20,
  against 660 ms for Rust (47.4×). Erlang (31.7 s) and Elixir (31.6 s) are within noise of it:
  their min-max ranges overlap Cheby's. Clojure (27.9 s) and Gleam (24.5 s) are faster, Koka
  (14.0 s) by 2.23× and OCaml (2.52 s) by 12.4×. Cheby's peak RSS is 39.8 MB: well under Erlang
  and Elixir (about 320 MB), Gleam (247 MB) and Clojure (2.1 GB), but over Rust's 11.3 MB.
- **Without mutation there is no linked list, by design.** Cheby has no mutable state (D-017), so
  neither shape B's doubly linked list nor an in-place `LinkedHashMap` can be written. Its
  shape A, `std::ordered_map`, is shape C inside: a `Map<K, (Int, V)>` plus a
  `SortedMap<Int, K>` from insertion number to key (`std/ordered_map.cheby`, D-336). So the rows
  to compare with are the other shape C rows (Erlang, Elixir, Clojure, Gleam, Koka), and Cheby
  lands among them.
- **A hit costs five hash operations and two tree updates.** `ordered_map` has no move-to-end, so
  a hit is `get`, `remove` and `insert` (D-340). `remove` and `insert` each start with their own
  `map::get`. A hit is therefore three hash lookups, a hash remove, a hash insert, and a
  `sorted_map::remove` and `insert`. A miss in a full cache also pays for `first` and the evict:
  four lookups, a hash remove, a hash insert and three tree operations in all. Every `map::get`
  that finds its key also allocates a `Some`. A move-to-end or pop-first operation in the standard
  library would save part of this work.
- **The cache is updated in place, but each step walks a tree.** Only the loop holds the cache,
  so Perceus reuse writes rebuilt tree nodes over the old ones and the hash trie changes in place.
  A test-size run with `CHEBY_RT_STATS=1` reported no copied map update. What is left is the work
  itself. Without mutation, an O(log n) weight-balanced tree (`std/sorted_map.cheby`) stands where
  shape B has an O(1) linked list. That tree compares keys through the `Compare` dictionary
  (D-046), because generic code is not yet specialized (D-021); specialization is planned for M6
  (D-251). In a profile at a tenth of the bench operations, JIT-compiled Cheby took about three
  fifths of the samples, the runtime's hash kernels about a fifth, and its allocation and
  reference counting about a seventh. Persistence alone does not explain the gap: Koka's
  persistent tree is 2.23× faster here.
- **The runtime adds one avoidable cost per update.** `Path::walk` in
  `crates/cheby_runtime/src/hamt/ops.rs` allocates two `Vec`s for every `map::insert` and
  `map::remove`, to record the path it walks. This belongs to the current implementation.
- **The rows use three shapes.** Java, Scala, Ruby, Python and Cheby use an ordered map (A). Rust,
  C++, Go, C#, TypeScript, Swift, Zig, Odin, Nim and OCaml use a hash map plus a linked list (B).
  The BEAM languages, Clojure and Koka use two persistent maps (C), and Koka writes its own tree.
  Cheby's estimate makes no difference here: the size-0 run takes 15 ms against a 31.3 s whole
  run.
- **Ruby beats two shape B rows with a plain `Hash`.** Its delete-and-reinsert hit (2.06 s) is
  faster than OCaml (2.52 s) and TypeScript (2.65 s), which both keep a hash map plus a linked list.
