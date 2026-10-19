- **Cheby finishes in 9.9 ms, 10th of 20 and 9.37× Rust.** All nine AOT languages take 1.1 to 1.7 ms
  (OCaml 1.5 ms, Go 1.7 ms). Cheby is faster than every VM and interpreter: Python takes 18 ms, Java
  22 ms, and the BEAM languages 87 to 105 ms (Gleam, Erlang, Elixir), 8.80× to 10.6× Cheby's time.
  Its peak RSS is 18.9 MB, against 1.6 to 4.2 MB for the AOT executables and about 71 MB for the
  BEAM languages.
- **Cheby's compile and start-up columns are the same measurement.** There is no build step before
  M3, so the ≈ 9.1 ms "compile" is the size-0 run of the program: parse, type-check, JIT-compile and
  run, on every start. It is the lowest compile time in the table, 0.10× Rust's 92 ms, because Cheby
  writes no executable, links nothing and generates unoptimised code (Cranelift with its optimiser
  off, D-259). Read it as the time from source to output, not as a build time.
- **Most of the start-up is checking the standard library, not the program.** `cheby check` alone
  takes 8.0 ms, 88% of the 9.1 ms start-up and 81% of the 9.9 ms run. About 2 to 3 ms of that is
  launching and exiting the process (`cheby --version` in a local test), so parsing and checking
  take roughly 5 to 6 ms, almost all of it std. Every module of a package depends implicitly on the
  std home module of each prelude type (D-447): `std::int`, `std::float`, `std::string`,
  `std::list`, `std::map`, `std::set`, `std::bytes`, the sized integer modules and others. With
  `std::io` and `std::ops`, this run checks 23 std modules (counted from a `CHEBY_DUMP_DIR` dump).
  Their sources are embedded in the binary, so every run parses and checks them again (D-450). In a
  local test, an empty `main` with no import checked nearly as fast as this program. This is the
  current implementation: M3 is to ship std precompiled (D-256).
- **Code generation is a small part of it.** The JIT compiles only what `main` reaches (D-510):
  `main`, `io::println` and a few `std::io` functions, shims and entry trampolines, 15 functions in
  all. Code generation plus starting and stopping the runtime is what separates `cheby check` from a
  run: 1.1 ms against the start-up series and 1.9 ms against the run series, so about 1 to 2 ms.
- **Most of the memory is front-end work on std, not the binary.** In a local test, launching
  `cheby` and exiting at once (`cheby --version`) peaked at about 3.4 MB, and took a little longer
  than Rust's whole hello world. `cheby check`, which parses and checks the std modules, peaks at
  15.5 MB, and code generation plus the runtime add the rest of the 18.9 MB.
- **M3 changes both columns.** `cheby build` will write an executable, so Cheby's compile becomes a
  real build time and its start-up no longer includes the front end. `cheby run` is to load cached
  machine code per module and compile lazily (D-254).
- **Cheby's run and start-up numbers are two series of the same command.** They differ by 0.8 ms
  (9.9 ms against 9.1 ms) for reasons outside the program: the run series was measured first and
  scattered more. So the run-time estimate, run minus start-up, means nothing here, and no split
  finer than about 1 ms can be read from this data.
- **Zig's 5.70 s compile includes its standard library.** Zig builds the program and its standard
  library as one optimised unit and cannot reuse a compiled std (CONVENTIONS.md). Its executable
  runs in 1.3 ms (start-up 1.4 ms), like the other AOT languages.
