- **Cheby runs the 200-module project in ≈ 242 ms, 4th of 19.** Only Ruby (89 ms), TypeScript's
  `tsc` (99 ms) and Python (234 ms) are faster, and none of them compiles the project to machine
  code. Rust's clean release build takes 6.79× as long (1.64 s), Erlang 3.06× (739 ms), Gleam 3.38×
  (818 ms), Go 12.4× (2.99 s) and OCaml 56.7× (13.7 s). At M = 1 Cheby is the fastest row, at
  ≈ 11 ms. Koka is not ranked, because its build fails at M = 200.
- **On CPU time, Cheby trails Ruby, Python and `tsc`, and beats every other row.** The run used
  1.25 s of CPU time (user plus system), about five cores busy for 242 ms, against 87 ms for Ruby,
  234 ms for Python and 448 ms for `tsc`. Per module (the slope from M = 1 to M = 200, from the
  JSON) Cheby adds 1.2 ms of wall time and 6.1 ms of CPU time. Ruby adds 0.30 ms and Python 1.1 ms
  of both, on one core. `tsc` adds 0.32 ms of wall and 1.6 ms of CPU time, Erlang 2.6 ms and 16 ms,
  and Rust 7.7 ms and 29 ms.
- **The front end is about a fifth of the time.** `cheby check` of the same project takes 47 ms (a
  slope of 0.19 ms per module from M = 1 to M = 200) and 201 ms of CPU. The rest is the back end and
  start-up: `cheby run` lowers all 4,000 functions (20 × 200) to MIR and compiles each with
  Cranelift before `main` runs. Lazy compilation and cached module code come with M3 (D-254), but
  `main` calls every function here, so a clean run would still compile them all. Cheby's own budget
  is 100k lines per second per core for checking plus code generation (D-247), and D-889 reads about
  90k on `bench/gen` projects, from in-process 1-thread builds. A 1-thread `cheby run -j 1` of this
  project took about 0.9 s (SPEC.md), about 37k lines per second with start-up and constant
  evaluation included. The default run's 1.25 CPU seconds also include the cost of running in
  parallel, so they do not compare with D-889.
- **Each small function becomes a lot of machine code (current implementation).** A `step_j` of
  seven body lines expands to several hundred lines of Cranelift IR (from a `CHEBY_DUMP_DIR` dump at
  M = 2). Every `+`, `*`, `/` and `%` is checked, because overflow panics (D-025, language design),
  and each source location gets one cold panic path for each kind of panic. Cheby's back end emits
  the zero and overflow tests even for a literal divisor (`cheby_codegen_clif/src/arith.rs`), and
  with Cranelift's optimiser off (D-259) nothing folds them, so `a / 31` keeps both. Every function
  returns one uniform word (D-453), so each call to `base` or `step_j` is followed by a tag test and
  an inline reference-count drop of the result. Each call also goes through the JIT's indirection
  slot (D-043).
- **The module constant `modulus` costs the most avoidable work.** It has 45 uses per module. Today
  a constant's value is linked in as data, not folded into the code (D-257 sets this for debug
  builds), and the JIT fills its slot only after compiling (D-535). So each use loads the slot,
  checks that it was filled, and `dup`s, unboxes and `drop`s the value, although the initializer is
  a literal. This is the current implementation: D-257 lets release builds export small scalar
  values like this one so they can be folded. In a scratch copy at a smaller M with the constant
  replaced by the literal, the back end ran markedly faster and the machine code was markedly
  smaller. SPEC.md asks for a named constant, so idiomatic code pays this cost today.
- **The rows do not do the same work.** Cheby's number is a whole `cheby run`: start-up, unoptimised
  code generation into memory (the debug profile, D-259) and a trivial `main`. It writes no file and
  links nothing, while the slower rows are release builds that write their output and, for the AOT
  languages, optimise and link it. D-267 lets a future Cheby release build take up to 3× its debug
  build. The rows ahead of Cheby are closer kin: `tsc` checks and emits JavaScript, and Python and
  Ruby compile to bytecode in memory.
- **Several toolchains build almost serially.** At M = 200, Go, Swift and OCaml used about 1.5, 1.4
  and 1.3 cores on average (CPU time over wall time), held back by the import chain (SPEC.md). Odin
  and Zig, which build one compilation unit, used about one. C++ under `make -j` used about 7.
