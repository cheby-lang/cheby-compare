- **Cheby is the slowest of the 20, at ≈ 4.53 s and 29.2× Rust.** The other languages without
  mutable arrays are ahead: Koka 1.78 s (Cheby 2.54×), Erlang 1.27 s (3.56×), Elixir 1.32 s (3.42×),
  Gleam 1.57 s (2.88×) and Clojure 3.11 s (1.46×). Python (3.06 s) is also ahead, by 1.48×. The SPEC
  holds the bench size at `N = 10`: at 11, Cheby took about 155 s, past the 120-second timeout in
  force when the size was chosen (it is 300 s now).
- **No mutable arrays is language design.** Cheby has no array type and no mutation (D-017, D-039),
  so the program flips and rotates a `List` with `list::get` and `list::set`. `list::set` updates in
  place when the list is unique (spec §9.3), and the runtime counters confirm it: almost every
  update is in place. The only copy is the first write of each permutation's flips, since `perm1`
  still holds the list, exactly as the SPEC predicts.
- **Every `list::get` allocates.** It returns an `Option` (D-318), and `cheby_list_get` in
  `crates/cheby_runtime/src/list/kernels.rs` allocates a fresh `Some` for every element it finds.
  The program's `list_at` unwraps it at once. Counting the reads of the algorithm against the
  runtime's allocation counter shows that these `Some` cells are most of the program's allocations.
  `std::list` has no indexed read without the `Option`. That is current implementation: the `Some`
  exists only to be unwrapped at once.
- **Every read and write is an out-of-line call into the RRB tree.** `list::get` and `list::set` are
  native externals (`std/list.cheby`), so each one is a runtime call that walks the tree and, for a
  write, checks that the list is unique. A profile splits the time between allocating and freeing
  the `Some` cells, these list kernels and compiled code. Koka's `vector<int>` follows the same
  rule, copying on a flip's first write and updating in place after it (its `impl.toml`), and Cheby
  takes 2.54× as long.
- **The code is the longest of the 20, at 97 lines.** Index updates need small helpers (`list_at`,
  `swap_inward`, `rotate_prefix`) and a `Step` type to carry the next permutation, where the array
  languages write a few loops.
- **Cheby's row is an estimate, with little noise.** It is the bench run minus a ≈ 11 ms size-0 run,
  with ten timings from 4.47 s to 4.63 s. Peak RSS is 20.8 MB, against 1.7 MB for Rust, and 18.9 MB
  of it is the floor of any `cheby run` process (`hello_world`). The compile estimate relies on
  eager JIT, since size 0 runs no flip (see the SPEC).
