- **Cheby runs ≈ 44.0 s, 19th of 20 and 85.6× Rust.** Only Python (51.4 s) is slower. The languages
  that rebuild immutable records in a list every step are its real peers, and Cheby trails all of
  them: Erlang 17.2 s (Cheby 2.56×), Elixir 23.8 s (1.85×), Gleam 26.2 s (1.68×) and Koka 2.78 s
  (15.8×). OCaml, with mutable float fields, runs 906 ms.
- **The language rules out the in-place version.** Cheby has no mutation and no array type (D-017,
  D-039), so each step builds new `Body` records and a new list, as the SPEC expects. Koka's 2.78 s
  shows how fast immutable records can run under Perceus reuse (D-005). Its list is a cons list
  walked by direct recursion, the shape a later bullet finds several times faster in Cheby too.
- **The time goes to lists, allocation and reference counting, not to float arithmetic.** A profile
  at a smaller step count puts most samples in the runtime's allocation and count functions and in
  its `List` kernels, with only a small share in compiled code. `List` is an RRB vector, not a
  linked list (D-039). Each `[first, ..rest]` pattern costs three runtime calls (`ListLength`,
  `ListGet`, `ListSliceOwned` in `crates/cheby_mir/src/ir.rs`). `list::fold` calls its closure
  through the uniform convention for unknown callees (D-453) and threads a fresh tuple accumulator.
  Each step also pushes and prepends to lists and maps over one.
- **Records read out of a `List` are often still shared, so their update cannot reuse them in
  place.** `cheby run --reuse-report` shows that `Body { ..a, ... }` may reuse `a` when it is
  unique, but `ListGet` dups the element it reads, and the runtime counters show many of those
  reuses missing at run time. The same step written over a hand-made cons type, the shape Koka and
  the BEAM programs use, reused every record in place and ran several times faster in a scratch test
  at a smaller size. That gap is current implementation, not language design.
- **Floats are mostly not boxed here.** A record keeps its `Float` fields raw (D-562,
  `docs/plan/architecture.md`), so reading and building bodies moves no boxed floats. The exception
  is `float::sqrt`, once per pair: a native external returns through a Cheby-ABI wrapper as a
  uniform word (D-455, D-453), so its result is a boxed `Float`. It is a small share of the profile.
- **Cheby's row is an estimate, from 3 timings.** It is the bench run minus a ≈ 11 ms size-0 run,
  which is negligible here, and runs over 5 s get only 3 timings. Peak RSS is 21.4 MB, against
  1.8 MB for Rust, and 18.9 MB of it is the floor of any `cheby run` process (`hello_world`).
