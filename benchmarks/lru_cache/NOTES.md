- **Cheby runs in 25.8 s as an executable and 26.5 s under `cheby run`, about 40× Rust.** The rows
  are 17th and 18th of 21, against 660 ms for Rust. Cheby sits among the other rows that keep two
  persistent maps. Gleam (24.5 s) is just ahead, and Clojure (27.9 s), Elixir (31.6 s) and Erlang
  (31.7 s) are behind. Koka (14.0 s) is 1.84× faster and OCaml (2.52 s) 10.2×. The executable's peak
  RSS is 18.2 MB, and `cheby run`'s is 33.4 MB: well under Erlang and Elixir (about 320 MB), Gleam
  (247 MB) and Clojure (2.1 GB), but over Rust's 11.3 MB. The October JIT took 31.3 s.
- **Without mutation there is no linked list, by design.** Cheby has no mutable state (D-017), so
  neither shape B's doubly linked list nor an in-place `LinkedHashMap` can be written. Its shape A,
  `std::ordered_map`, is shape C inside: a `Map<K, (Int, V)>` plus a `SortedMap<Int, K>` from
  insertion number to key (`std/ordered_map.cheby`, D-336). So the rows to compare with are the
  other shape C rows (Erlang, Elixir, Clojure, Gleam, Koka), and Cheby lands among them.
- **A hit costs four hash operations and two tree updates.** `ordered_map` has no move-to-end, so a
  hit is `get`, `remove` and `insert` (D-340). `get` is a hash lookup. `remove` starts with its own
  lookup, then removes from the hash trie and from the tree. `insert` is one `map::upsert` and a
  tree insert. A miss in a full cache also pays for `first`, which reads the tree and looks the key
  up, and for the `remove` that evicts. Every `map::get` that finds its key also allocates a `Some`.
  A move-to-end or pop-first operation in the standard library would save part of this work.
- **Most of the time is the sorted tree, in compiled Cheby code.** A profile of the executable puts
  73% of the samples in compiled code, most of it `std::sorted_map`: `sorted_map::balanced` alone
  takes 19%. The runtime's hash-trie kernels take 19%, and allocation and reference counting 7%.
  Without mutation, an O(log n) weight-balanced tree (`std/sorted_map.cheby`) stands where shape B
  has an O(1) linked list. That tree compares keys through the `Compare` dictionary (D-046), because
  generic code is not yet specialized (D-021): `int::compare` and the shim that calls it take 12% of
  the samples. Specialization is planned for M6 (D-251). Persistence alone does not explain the gap:
  Koka's persistent tree is 1.84× faster here.
- **The cache is updated in place.** Only the loop holds the cache, so Perceus reuse writes rebuilt
  tree nodes over the old ones and the hash trie changes in place. The runtime counters
  (`CHEBY_RT_STATS=1`) report 809 million reuses against 8.6 million misses, and 39.9 million map
  updates in place, two per operation, with none copied.
- **The rows use three shapes.** Java, Scala, Ruby, Python and Cheby use an ordered map (A). Rust,
  C++, Go, C#, TypeScript, Swift, Zig, Odin, Nim and OCaml use a hash map plus a linked list (B).
  The BEAM languages, Clojure and Koka use two persistent maps (C), and Koka writes its own tree.
  Runs over 5 s get 3 timings: 25.6 s to 28.1 s for Cheby's executable and 25.5 s to 26.5 s for
  `cheby run`.
- **Ruby beats two shape B rows with a plain `Hash`.** Its delete-and-reinsert hit (2.06 s) is
  faster than OCaml (2.52 s) and TypeScript (2.65 s), which both keep a hash map plus a linked list.
