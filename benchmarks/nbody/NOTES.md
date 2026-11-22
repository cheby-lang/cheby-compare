- **Cheby runs in 27.2 s as an executable and 28.2 s under `cheby run`, about 53× Rust.** The rows
  are 18th and 19th of 21, ahead of Ruby (29.4 s) and Python (51.4 s). The languages that rebuild
  immutable records in a list every step are its peers. Cheby is now level with Gleam (26.2 s) and
  behind Elixir (23.8 s, Cheby 1.14×), Erlang (17.2 s, 1.58×) and Koka (2.78 s, 9.80×). OCaml, with
  mutable float fields, runs in 906 ms. The October JIT took 44.0 s.
- **The language rules out the in-place version.** Cheby has no mutation and no array type (D-017,
  D-039), so each step builds new `Body` records and a new list, as the SPEC expects. Koka's 2.78 s
  shows how fast immutable records can run under Perceus reuse (D-005). Its list is a cons list
  walked by direct recursion.
- **The time goes to allocation, reference counting and lists, not to float arithmetic.** A profile
  of the executable puts 42% of the samples in the runtime's allocation and counting code, 24% in
  its `List` code and 26% in compiled code. The runtime counters (`CHEBY_RT_STATS=1`) report 63
  allocations per step: 1.39 billion over 22 million steps. `List` is an RRB vector, not a linked
  list (D-039). `list::fold` calls its closure through the uniform convention for unknown callees
  (D-453) and threads a fresh tuple accumulator. Each step also pushes and prepends to lists and
  maps over one.
- **Every record update now reuses its record in place.** The counters report 770 million reuses and
  no miss. They also report 220 million list pushes and 704 million list updates in place, against
  10 copies. In October many of these reuses missed at run time. A `[first, ..rest]` step cost three
  runtime calls then. Now the compiler writes the step inline for a list that nothing else holds,
  and calls the runtime once for any other list (D-1757 to D-1760).
- **A cons list may still be faster, but that is not measured.** In an October scratch test, the
  same step over a hand-made cons type, the shape Koka and the BEAM programs use, ran several times
  faster. Nobody has repeated the test since the list changes, so the size of that gap today is
  unknown.
- **Floats are mostly not boxed here.** A record keeps its `Float` fields raw (D-562,
  `docs/plan/architecture.md`), so reading and building bodies moves no boxed floats. The exception
  is `float::sqrt`, once per pair: a native external returns through a Cheby-ABI wrapper as a
  uniform word (D-455, D-453), so its result is a boxed `Float`. Boxing takes under 3% of the
  samples.
- **The executable needs little memory.** It peaks at 3.8 MB, against 1.8 MB for Rust. `cheby run`
  peaks at 18.4 MB, and 16.4 MB of that is the floor of any `cheby run` process (`hello_world`).
  Runs over 5 s get 3 timings: 27.2 s to 27.3 s for the executable and 28.1 s to 30.3 s for `cheby
  run`.
