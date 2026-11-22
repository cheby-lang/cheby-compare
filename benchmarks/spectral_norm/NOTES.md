- **Cheby runs in 21.5 s on both rows, 27× Rust.** The rows are 18th and 19th of 21, ahead of Ruby
  (50.4 s) and Python (77.4 s, one timing). The list-walking languages are the fair comparison, and
  all are ahead: Gleam 18.1 s (Cheby 1.19×), Elixir 9.51 s (2.26×), Erlang 8.58 s (2.50×) and Koka
  5.96 s (3.60×). The October JIT took 52.6 s.
- **No arrays is language design, and it shapes the program.** Cheby has no array type (D-039), so
  the vectors are `List<Float>` walked front to back, as in the BEAM languages and Koka. A `Float`
  inside a `List` is a boxed heap object (D-521), so every element read touches a separate object
  and updates its count.
- **`float::from_int` allocates on every matrix entry.** It is a native external, and a native
  external is called through a Cheby-ABI wrapper that returns one uniform word (D-455, D-453). Its
  `Float` result is boxed, then unboxed and freed by the caller. The runtime counters
  (`CHEBY_RT_STATS=1`) report 1.21 billion allocations, one per inner step: 40 passes over 5,500²
  entries. A profile of the executable puts 41% of the samples in allocating, counting and freeing.
  In an October scratch test at a smaller `n`, carrying the indices as `Float`, with no conversion
  in the inner loop, cut the run time by more than half. That test has not been repeated. The cost
  is current implementation.
- **A `[xj, ..tail]` step is one runtime call here, down from three.** The compiler writes the step
  inline for a list whose leaf nothing else holds (D-1759). Here every row walks the same vector, so
  its leaves stay shared and each step calls `cheby_rt_list_uncons_owned`, which takes 13% of the
  samples. The first step of every row copies the root of the shared list: the counters report
  220,002 copies, one per row, against 1.21 billion steps in place. The runtime's list code takes
  18% of the samples in all, and compiled code 33%.
- **The program is already tuned around the boxing.** `A(i, j)` is written out in both inner loops
  instead of being a helper, because a `Float` returned from a function is boxed (D-453). The Cheby
  `impl.toml` records the measurement behind that choice.
- **Boxed float returns are not unique to Cheby.** OCaml marks its entry helper `[@inline]`, since
  `ocamlopt` without flambda boxes a returned float, and Erlang and Elixir ask their compilers to
  inline `a/2` (their `impl.toml` files).
- **The executable needs little memory.** It peaks at 4.7 MB, against 1.9 MB for Rust. `cheby run`
  peaks at 19.1 MB, and 16.4 MB of that is the floor of any `cheby run` process (`hello_world`).
  Runs over 5 s get 3 timings: 21.3 s to 22.0 s for the executable and 21.4 s to 21.6 s for `cheby
  run`.
