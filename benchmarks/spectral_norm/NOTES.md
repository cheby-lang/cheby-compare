- **Cheby runs ≈ 52.6 s, 19th of 20 and 65.5× Rust.** Only Python (77.4 s, one timing) is slower,
  and Ruby (50.4 s) is just ahead (Cheby 1.04×). The list-walking languages are the fair comparison, and all
  are ahead: Erlang 8.58 s (Cheby 6.13×), Elixir 9.51 s (5.53×), Gleam 18.1 s (2.90×) and Koka
  5.96 s (8.82×).
- **No arrays is language design, and it shapes the program.** Cheby has no array type (D-039), so
  the vectors are `List<Float>` walked front to back, as in the BEAM languages and Koka. A `Float`
  inside a `List` is a boxed heap object (D-521), so every element read touches a separate object
  and updates its count.
- **`float::from_int` allocates on every matrix entry.** It is a native external, and a native
  external is called through a Cheby-ABI wrapper that returns one uniform word (D-455, D-453), so
  its `Float` result is boxed, then unboxed and freed by the caller. The runtime counters show one
  allocation per inner step. In a scratch test at a smaller `n`, carrying the indices as `Float`,
  with no conversion in the inner loop, cut the run time by more than half. That cost is current
  implementation.
- **Each `[xj, ..tail]` step is three runtime calls.** A list pattern lowers to `ListLength`,
  `ListGet` and `ListSliceOwned` (`crates/cheby_mir/src/ir.rs`), none of them inlined, and the first
  slice of every row copies the root of the shared input list. A profile puts the largest share of
  samples in these list kernels, then in allocating and freeing the boxed floats, and the smallest
  in compiled code. In the same scratch test, a hand-made cons type with raw `Float` fields also
  saved about half, and the two changes together removed most of the run time. So both costs are
  current implementation, not the arithmetic.
- **The program is already tuned around the boxing.** `A(i, j)` is written out in both inner loops
  instead of being a helper, because a `Float` returned from a function is boxed (D-453). The Cheby
  `impl.toml` records the measurement behind that choice.
- **Boxed float returns are not unique to Cheby.** OCaml marks its entry helper `[@inline]`, since
  `ocamlopt` without flambda boxes a returned float, and Erlang and Elixir ask their compilers to
  inline `a/2` (their `impl.toml` files).
- **Cheby's row is an estimate.** It is the bench run minus a ≈ 12 ms size-0 run, which is
  negligible here, and runs over 5 s get only 3 timings. Peak RSS is 21.4 MB, against 1.9 MB for
  Rust, and 18.9 MB of it is the floor of any `cheby run` process (`hello_world`).
