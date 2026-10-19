- **Cheby runs ≈ 2.12 s, 15th of 20 and 2.97× Rust.** This is its best CPU rank, and its
  second-best CPU ratio to Rust after binary_trees (1.34×). Every AOT, JVM, CLR and JS runtime is
  ahead of it: Cheby takes 2.20× as long as OCaml (963 ms), 2.21× as long as Clojure (962 ms) and
  2.75× as long as Koka (772 ms). It is ahead of the BEAM languages, which take 3.87× (Erlang,
  8.21 s) to 4.06× (Gleam, 8.61 s) as long, and of Ruby and Python.
- **The inner loop allocates nothing.** `escape_time` is a top-level function that calls itself in
  tail position, and a Cheby-ABI function keeps its `Float` parameters unboxed (D-453). The one
  allocation per point is the boxed result of `float::from_int`, a native external that returns
  through a uniform-word wrapper (D-455). The runtime counters show one allocation per point, and a
  profile puts only a small share of samples in allocating and freeing.
- **Every iteration is still a full function call.** The disassembly of the JIT code shows each step
  run the whole prologue and epilogue: it saves callee-saved registers, signs the return address,
  spills its four `Float` parameters to the stack and checks the stack limit (D-028, D-453). Then it
  adds 1 to `steps` with an overflow check (D-025) and jumps back through the function's indirection
  slot as a Cranelift `return_call`. On native every tail call, self calls included, goes through
  the slot so that REPL redefinitions stay visible (D-015, D-043). The planned JS target (M4) will
  compile self recursion to loops. Each step also loads the constant `max_iterations` from its slot,
  with a dup and a drop, and the `>` compare takes three `fcmp` instructions. The float math is only
  a handful of the instructions in each step. The call overhead and the constant load are current
  implementation.
- **The program shape works around the boxing rules.** The loops are top-level functions because a
  local function takes and returns uniform words (D-453), so every `Float` passing through it is
  boxed. The SPEC and Cheby's `impl.toml` record a local-loop version as several times slower. `cr`
  is computed inline and the totals are accumulator arguments, so no `Float` comes back from a call
  that is not a tail call, apart from `float::from_int`. That is why `walk` takes eight parameters,
  which, with loops written as recursion, accounts for much of Cheby's 66 lines against Rust's 41.
- **Cheby's row is an estimate, with little noise.** It is the bench run minus a ≈ 10 ms size-0 run,
  with ten timings from 2.09 s to 2.16 s. Peak RSS is 20.0 MB, against 1.8 MB for Rust, and 18.9 MB
  of it is the floor of any `cheby run` process (`hello_world`).
- **Outside Cheby, twelve runtimes finish within 1.10× of the fastest.** Swift, Odin, Zig, C++, Nim,
  Rust, Java, Go, TypeScript, C#, Scala and Koka all land between 705 ms and 772 ms. The loop is
  simple enough that the JVM, V8 and the CLR match the AOT compilers.
