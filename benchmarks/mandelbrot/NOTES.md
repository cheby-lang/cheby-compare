- **Cheby runs in 1.67 s on both rows, 2.34× Rust.** The rows are 15th and 16th of 21. This is
  Cheby's second-best CPU ratio to Rust, after `binary_trees` (1.05×). Every AOT, JVM, CLR and JS
  runtime is ahead of it: Cheby takes 1.74× as long as OCaml (963 ms) and Clojure (962 ms), and
  2.17× as long as Koka (772 ms). It is ahead of the BEAM languages, which take 4.9× (Erlang, 8.21
  s) to 5.1× (Gleam, 8.61 s) as long, and of Ruby and Python.
- **The inner loop allocates nothing.** `escape_time` is a top-level function that calls itself in
  tail position, and a Cheby-ABI function keeps its `Float` parameters unboxed (D-453). The one
  allocation per point is the boxed result of `float::from_int`, a native external that returns
  through a uniform-word wrapper (D-455). The runtime counters report 16.0 million allocations for
  4,000² points, and a profile of the executable puts 6% of the samples in allocating and freeing.
  Compiled code takes 93%.
- **Every iteration is still a full function call.** The disassembly of the executable shows each
  step run the whole prologue and epilogue: it saves callee-saved registers, spills its four `Float`
  parameters to the stack and checks the stack limit (D-028, D-453). Then it adds 1 to `steps` with
  an overflow check (D-025) and jumps back through the function's slot, as a Cranelift `return_call`
  to an address it loads first. Every native tail call goes through the slot, self calls included,
  so that REPL redefinitions stay visible (D-015, D-043). The executable keeps the slot too. The
  planned JS target (M4) will compile self recursion to loops. Each step also loads the constant
  `max_iterations` from its slot, checks that the slot is filled, and does a dup and a drop. The `>`
  compare takes three `fcmp` instructions. The float math is only a handful of the instructions in
  each step. The call overhead and the constant load are current implementation.
- **The program shape works around the boxing rules.** The loops are top-level functions because a
  local function takes and returns uniform words (D-453), so every `Float` passing through it is
  boxed. The SPEC and Cheby's `impl.toml` record a local-loop version as several times slower. `cr`
  is computed inline and the totals are accumulator arguments, so no `Float` comes back from a call
  that is not a tail call, apart from `float::from_int`. That is why `walk` takes eight parameters.
  With loops written as recursion, that accounts for much of Cheby's 66 lines against Rust's 41.
- **Both rows are steady, and the executable needs little memory.** Ten timings span 1.67 s to 1.68
  s for `cheby run` and 1.67 s to 1.70 s for the executable. The executable peaks at 3.7 MB, against
  1.8 MB for Rust. `cheby run` peaks at 16.7 MB, and 16.4 MB of that is the floor of any `cheby run`
  process (`hello_world`).
- **Outside Cheby, twelve runtimes finish within 1.10× of the fastest.** Swift, Odin, Zig, C++, Nim,
  Rust, Java, Go, TypeScript, C#, Scala and Koka all land between 705 ms and 772 ms. The loop is
  simple enough that the JVM, V8 and the CLR match the AOT compilers.
