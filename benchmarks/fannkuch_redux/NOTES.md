- **Cheby has the two slowest rows: 3.56 s under `cheby run` and 3.74 s as an executable, 23× and
  24× Rust.** Their timings overlap, 3.45 s to 3.73 s against 3.58 s to 3.86 s, so neither row is
  the faster one. The other languages without mutable arrays are ahead: Erlang 1.27 s (Cheby 2.80×),
  Elixir 1.32 s (2.69×), Gleam 1.57 s (2.27×), Koka 1.78 s (2.00×) and Clojure 3.11 s (1.15×).
  Python (3.06 s) is also ahead, by 1.16×. The SPEC holds the bench size at `N = 10`: at 11, the
  October JIT took about 155 s, past the 120-second timeout in force when the size was chosen (it is
  300 s now). The October JIT took 4.53 s at 10.
- **No mutable arrays is language design.** Cheby has no array type and no mutation (D-017, D-039),
  so the program flips and rotates a `List` with `list::get` and `list::set`. `list::set` updates in
  place when the list is unique (spec §9.3), and the runtime counters (`CHEBY_RT_STATS=1`) confirm
  it: 137.7 million updates in place against 3.27 million copies. The only copy is the first write
  of each permutation's flips, since `perm1` still holds the list, exactly as the SPEC predicts.
- **Every `list::get` allocates.** It returns an `Option` (D-318), and `cheby_list_get` in
  `crates/cheby_runtime/src/list/kernels.rs` allocates a fresh `Some` for every element it finds.
  The program's `list_at` unwraps it at once. The run makes 154.7 million allocations, and counting
  the reads of the algorithm shows that these `Some` cells are most of them. `std::list` has no
  indexed read without the `Option`. That is current implementation: the `Some` exists only to be
  unwrapped at once.
- **Every read and write is an out-of-line call into the RRB tree.** `list::get` and `list::set` are
  native externals (`std/list.cheby`), so each one is a runtime call that walks the tree and, for a
  write, checks that the list is unique. A profile of the executable splits the time three ways: 35%
  in compiled code, 31% in these list kernels, and 30% in allocating and freeing the `Some` cells.
  Koka's `vector<int>` follows the same rule, copying on a flip's first write and updating in place
  after it (its `impl.toml`), and Cheby takes 2.00× as long.
- **The code is the longest of the 21 rows, at 97 lines.** Index updates need small helpers
  (`list_at`, `swap_inward`, `rotate_prefix`) and a `Step` type to carry the next permutation, where
  the array languages write a few loops.
- **The executable needs little memory.** It peaks at 3.9 MB, against 1.7 MB for Rust. `cheby run`
  peaks at 18.4 MB, and 16.4 MB of that is the floor of any `cheby run` process (`hello_world`).
