- **Cheby's executable finishes in 1.5 ms, 6th of 21, among the other AOT languages.** They take 1.1
  ms (Rust) to 1.7 ms (Go). `cheby run` takes 6.1 ms as a whole process, 11th of 21. That is slower
  than every AOT executable and faster than every VM and interpreter: Python takes 18 ms, Java 22
  ms, and the BEAM languages 87 ms to 105 ms (Gleam, Erlang, Elixir).
- **The executable peaks at 3.5 MB, and `cheby run` at 16.4 MB.** The other AOT executables peak at
  1.6 MB to 4.2 MB, and the BEAM languages at about 71 MB. The 16.4 MB is the floor of every `cheby
  run` process, which carries the compiler and the JIT. The other benchmarks' notes cite it as that
  floor.
- **`cheby build` takes 55 ms, the second-lowest compile time in the table.** Only TypeScript's
  `tsc` (35 ms) is lower, and Rust takes 92 ms. The build starts from a cache that holds the
  standard library, as other languages keep theirs compiled. It compiles the program and links it,
  and the link is most of the time (README, "Cheby's two rows"). The debug profile is the only one
  until M6, so the code is unoptimised. The executable is 1.2 MB, against 460 KB for Rust and 2.4 MB
  for Go.
- **`cheby run` spends most of its 6 ms before the program starts.** In a local test with a warm
  cache, `cheby --version` took 1.8 ms, `cheby check` of this program 4.9 ms, and `cheby run` 5.8
  ms. So launching the process costs about 2 ms, the front end about 3 ms, and loading the cached
  code and running it about 1 ms. `cheby run` has no compile column: with the program's code in the
  cache it compiles nothing.
- **The October JIT took 9.9 ms, most of it checking the standard library.** Every run parsed and
  checked the 23 std modules this program pulls in. Since M3, std comes from the build cache, and
  `cheby build` removes the front end from start-up.
- **The run and start-up columns are two series of the same command.** For the executable they read
  1.5 ms and 1.7 ms. The difference is noise, so no split finer than a few tenths of a millisecond
  can be read from this data.
- **Zig's 5.70 s compile includes its standard library.** Zig builds the program and its standard
  library as one optimised unit and cannot reuse a compiled std (CONVENTIONS.md). Its executable
  runs in 1.3 ms (start-up 1.4 ms), like the other AOT languages.
