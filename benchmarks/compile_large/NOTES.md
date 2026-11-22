- **A cold `cheby run` of the 200-module project takes 571 ms, 4th of the 20 ranked rows, and `cheby
  build` takes 716 ms, 5th.** Only Ruby (89 ms), TypeScript's `tsc` (99 ms) and Python (234 ms) are
  faster, and none of them compiles the project to machine code. Erlang takes 739 ms and Gleam 818
  ms. Rust's clean release build takes 1.64 s, 2.29× the Cheby build. Go takes 2.99 s (4.18×) and
  OCaml 13.7 s (19.1×). At M = 1 `cheby run` takes 19 ms, level with Python (20 ms) and ahead of
  every other row. Koka is not ranked, because its build fails at M = 200.
- **Both rows now fill the build cache, which the October JIT did not have.** In October `cheby run`
  compiled the project into memory in 242 ms and kept nothing. Now a cold run also stores each
  module's compiled code: in a scratch run the cache grew from 4 MB to 42 MB. The second run of the
  same project took 106 ms.
- **The module constant costs half of the cold time.** Every module declares `priv const modulus:
  Int = 1000003` and uses it 45 times. Each constant is evaluated on code compiled in a JIT module
  of its own, and stored as a cache entry of its own (D-977 to D-979). Module code reads a constant
  only through its slot, so each use loads the slot, checks that it is filled, and dups and drops
  the value. In a scratch copy with the constant replaced by the literal, a cold `cheby run` took
  262 ms against 538 ms, a cold `cheby check` 59 ms against 302 ms, and a cold `cheby build` 346 ms
  against 757 ms. The executable shrank from 11.5 MB to 9.4 MB. D-257 lets release builds fold small
  scalar constants like this one. SPEC.md asks for a named constant, so idiomatic code pays this
  cost today.
- **On CPU time, Cheby is level with Erlang and Gleam.** The cold run used 3.01 s of CPU time (user
  plus system), about five cores busy for 571 ms. Ruby used 87 ms and Python 234 ms, each on one
  core, and `tsc` 448 ms. Erlang used 3.66 s, Gleam 3.70 s and Rust 5.83 s. Per module (the slope
  from M = 1 to M = 200, from the JSON) `cheby run` adds 2.8 ms of wall time and 15 ms of CPU time,
  and `cheby build` 3.3 ms and 16 ms. Ruby adds 0.31 ms and Python 1.1 ms of both. `tsc` adds 0.32
  ms of wall and 1.6 ms of CPU time, Erlang 2.6 ms and 16 ms, and Rust 7.7 ms and 29 ms.
- **The front end is half of the cold run.** A cold `cheby check` of the project takes 304 ms and 15
  ms at M = 1, a slope of 1.5 ms per module. Most of it is the 200 constants: the scratch copy
  without them checked in 59 ms. On a warm cache `cheby check` took 86 ms.
- **One thread is not the budget's measurement.** A cold `cheby run -j 1` took 1.92 s for the
  project's 33,008 lines, about 17k lines per second. Cheby's own budget is 100k lines per second
  per core for checking plus code generation (D-247). This row is a whole process: it also starts
  up, evaluates 200 constants, writes the cache and runs `main`.
- **The rows do not do the same work.** `cheby run`'s number is a whole process: start-up,
  unoptimised code generation (the debug profile, D-259), cache writes and a trivial `main`. `cheby
  build` also links an executable, still unoptimised. The slower rows are release builds that
  optimise their output. D-267 lets a future Cheby release build take up to 3× its debug build. The
  rows ahead of Cheby are closer kin to `cheby run`: `tsc` checks and emits JavaScript, and Python
  and Ruby compile to bytecode in memory.
- **Several toolchains build almost serially.** At M = 200, Go, Swift and OCaml used about 1.5, 1.4
  and 1.3 cores on average (CPU time over wall time), held back by the import chain (SPEC.md). Odin
  and Zig, which build one compilation unit, used about one. C++ under `make -j` used about 7.
