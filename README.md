# cheby-compare

Benchmarks that compare [Cheby](../cheby), a pre-1.0 functional language, with 19 other
languages. Each benchmark has one implementation per language, written idiomatically and
following the same algorithm. A Python runner builds them, checks their output and measures run
time, compile time, start-up, peak memory, artifact size and lines of code.

The rules every implementation and tool follows are in [CONVENTIONS.md](CONVENTIONS.md). Read it
before adding or changing an implementation.

## Languages

| Id                  | Language             | Kind        | Notes                                                   |
| ------------------- | -------------------- | ----------- | ------------------------------------------------------- |
| `cheby`             | Cheby                | JIT         | `cheby run`, whole process with a warm cache, see below |
| `cheby-aot`         | Cheby (AOT)          | AOT         | `cheby build --release` of the same programs, see below |
| `gleam`             | Gleam                | BEAM        | concurrency through `gleam_erlang` and `gleam_otp`      |
| `rust`              | Rust                 | AOT         | the baseline of the summary ratios                      |
| `go`                | Go                   | AOT         |                                                         |
| `zig`               | Zig                  | AOT         |                                                         |
| `odin`              | Odin                 | AOT         |                                                         |
| `cpp`               | C++                  | AOT         | Apple clang                                             |
| `erlang`            | Erlang               | BEAM        |                                                         |
| `python`            | Python               | interpreter |                                                         |
| `java`              | Java                 | JVM         |                                                         |
| `typescript`        | TypeScript           | JS VM       | tsc, then node on the emitted JavaScript                |
| `swift`             | Swift                | AOT         |                                                         |
| `csharp`            | C#                   | CLR         | also gets a warm compile (the .NET build server)        |
| `elixir`            | Elixir               | BEAM        |                                                         |
| `scala`             | Scala                | JVM         | also gets a warm compile (Bloop)                        |
| `clojure`           | Clojure              | JVM         |                                                         |
| `koka`              | Koka                 | AOT         | see "Koka" below                                        |
| `ocaml`             | OCaml                | AOT         |                                                         |
| `nim`               | Nim                  | AOT         |                                                         |
| `ruby`              | Ruby                 | interpreter | runs with `--yjit`                                      |
| `rust-tokio`        | Rust (tokio)         | AOT         | library variant, concurrency benchmarks only            |
| `clojure-coreasync` | Clojure (core.async) | JVM         | library variant, concurrency benchmarks only            |
| `ocaml-eio`         | OCaml (Eio)          | AOT         | library variant, concurrency benchmarks only            |

The toolchain versions are in [CONVENTIONS.md](CONVENTIONS.md#languages), and
`python3 runner/run.py versions` prints the installed ones. Each language has a
`langs/<id>.toml` that says how to build, clean, run and measure it, a guide `langs/<id>.md` for
writing implementations, and, when it needs more than its Homebrew formula, `setup/<id>.sh`.

**Library variants.** For the three concurrency benchmarks (`ping_pong`, `spawn_many` and
`prime_sieve`), a well-known library changes the picture for some languages, so they get a second
row: tokio for Rust, core.async for Clojure and Eio for OCaml. A variant appears only in those three
benchmarks. The report labels it with its library, for example "Rust (tokio)". The variants get
their own summary table, because a geometric mean over three benchmarks does not compare with the
per-language means over all of them. Gleam has no concurrency in its standard library, so its main
row uses `gleam_erlang` and `gleam_otp`, and it has no variant.

### Koka

- **`compile_large` at the bench size is a known build failure.** Koka's generated C header for each
  module includes the header of every module it imports, so the chain of 200 modules nests 200
  headers deep. Apple clang stops at its fixed include-depth limit of 200 ("#include nested too
  deeply"; no flag raises it). Sizes `zero` and `test` build, and so do 199 modules. The report
  shows the reason, from `known_failure` in the implementation's `impl.toml`, instead of the raw
  error.
- **The three concurrency rows are measured but not comparable.** Koka's `std/async` schedules
  strands cooperatively on one thread and has no dynamic spawn, and `spawn_many` writes its own
  cooperative scheduler as an effect handler, as its SPEC says. The rows carry
  `comparable = false`: the report shows them, tagged "not comparable" with the reason as a
  footnote, and leaves them out of the geometric means and the "vs fastest" baselines.

## Benchmarks

| Benchmark        | Group         | What it shows                                             |
| ---------------- | ------------- | --------------------------------------------------------- |
| `binary_trees`   | CPU           | allocation and freeing of many small nodes                |
| `nbody`          | CPU           | floating point on a few records, many steps               |
| `spectral_norm`  | CPU           | floating point over vectors, O(n²) per step               |
| `mandelbrot`     | CPU           | tight float loops, no allocation                          |
| `fannkuch_redux` | CPU           | in-place permutation of a small array                     |
| `word_freq`      | data          | reading a file, splitting, hash map counting, sorting     |
| `json_roundtrip` | data          | parsing, walking and serializing a JSON document          |
| `lru_cache`      | data          | an LRU cache under a pseudo-random access stream          |
| `ping_pong`      | concurrency   | message passing between two lightweight tasks             |
| `spawn_many`     | concurrency   | spawning and joining many short tasks                     |
| `prime_sieve`    | concurrency   | a pipeline of filter tasks connected by channels          |
| `hello_world`    | compile speed | the smallest program: cold compile time and start-up      |
| `compile_large`  | compile speed | a generated project of many modules: compile-time scaling |

Each `benchmarks/<bench>/` holds `SPEC.md` (the algorithm and the exact output), `sizes.toml`
(the arguments for sizes `zero`, `test` and `bench`), `expected/<size>.out` and one directory per
language. `NOTES.md`, when present, goes into the report. An implementation's optional
`impl.toml` overrides its language's config and may add `libs`, `notes`, `comparable = false`
with a `comparable_note`, and `known_failure`.

## Running

### Setup

```sh
./setup.sh             # install what is missing, then run every setup/<lang>.sh
./setup.sh --check     # only report: missing tools, and which setup scripts would run
```

`setup.sh` installs the missing Homebrew toolchains, then runs each `setup/<lang>.sh`. A setup
script fetches its language's libraries, fills its caches and checks the paths its config uses,
so that builds work offline. Every step is idempotent, so run it again after changing a
language's dependencies. One failing script does not stop the others, and the failures are
listed at the end. It also builds `../cheby` in release mode when its binary is missing, and
`--build-cheby` rebuilds it.

Two toolchains stay off the default `PATH`, and the configs set them through `env`:

- The JDK is keg-only, at `/opt/homebrew/opt/openjdk/bin`. For a shell, add
  `export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"`.
- Homebrew's .NET needs `DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec`.

### Verify

```sh
python3 runner/run.py list               # languages, benchmarks, which implementations exist
python3 runner/run.py versions           # toolchain versions
python3 runner/run.py inputs             # generate inputs/data/ (word_freq, json_roundtrip)
python3 runner/run.py verify             # build, run sizes zero and test, diff with expected/
python3 runner/run.py verify --sizes zero,test,bench --diff -l cheby -b nbody
```

`verify` prints a matrix of languages against benchmarks, and with `--diff` the first lines
where an output differs.

### Measure

```sh
python3 runner/run.py measure                          # everything, into results/<date>.json
python3 runner/run.py measure -l cheby rust -b nbody   # a selection
python3 runner/run.py measure --out results/full.json  # a named results file
```

The runner saves the results file after every entry. **Measuring is resumable**: when the
`--out` file exists, the runner skips the entries it already holds, so a run that was
interrupted, or one that adds languages or benchmarks, continues where it stopped.
`--retry-failed` re-measures the entries that did not end `ok`, and `--redo` re-measures all of
them. `--quick` takes 3 runs without warm-up, for smoke tests only. A full run takes hours,
mostly for the slow interpreters and the compile benchmarks.

### Report

```sh
python3 runner/report.py                                   # the newest results/*.json
python3 runner/report.py results/full.json                 # a given results file
python3 runner/report.py results/quick.json --out-dir build/report-test
```

It writes `RESULTS.md` (the tables), `report/index.html` (charts that switch between log and
linear scale) and the summary in the Results section below. `--out-dir DIR` writes all three
under `DIR` instead, the summary as `DIR/README-results.md`, for test runs that must not touch
the real results. `--no-readme` leaves the README alone.

### Other options

- `-l LANG...` and `-b BENCH...` select languages and benchmarks, space or comma separated.
- `CHEBY=/path/to/cheby` uses another Cheby binary than `../cheby/target/release/cheby`.
- `--benchmarks-dir DIR` and `--build-root DIR`, before the subcommand, point the runner at
  another set of benchmarks, for example a scratch one to test the runner.
- `python3 runner/loc.py benchmarks/nbody/rust` counts one implementation's lines of code.

Build outputs go to `build/<lang>/<bench>/`, generated inputs to `inputs/data/`. Both are ignored
by git.

## Methodology

The full rules are in [CONVENTIONS.md](CONVENTIONS.md#measurement). In short:

- **Output first.** Every program's stdout at sizes `zero` and `bench` must match
  `expected/<size>.out` byte for byte before anything is timed. A wrong output is reported, not
  timed.
- **Integer output only.** Languages format floats differently, so every float is printed as an
  integer, `round(x * 10^k)` with `k` fixed by the spec. The outputs are byte-identical across
  languages.
- **Run time** is the median of 10 [hyperfine](https://github.com/sharkdp/hyperfine) runs after
  one warm-up, at the bench size, with min and max. A run over 5 s gets 3 runs, and one over
  60 s a single run, which the report marks "(n=1)"; the output check serves as their warm-up.
  A run over 300 s is recorded as a timeout.
- **Start-up** is the median run at size 0.
- **Compile time** is the median of 5 hyperfine runs of the build command, each after `clean`.
  It is the **cold** compile, with no build server running. It is the main compile number and
  the one in the summary, since Cheby and most languages have no server.
- **Warm compile** is a second column for the two languages whose normal workflow keeps a build
  server running: Scala (Bloop) and C# (the .NET build server and shared compiler). The runner
  starts the server, does three warm-up builds, then times five builds after `clean`.
- **Third-party libraries are not part of compile time.** `clean` removes only the program's own
  outputs and keeps the fetched and compiled dependencies (JSON libraries, tokio, core.async,
  Eio), so the number is the time to compile the program, not its libraries. For Cheby, `clean`
  resets its build cache to one that holds std (see "Cheby's two rows").
- **Ruby runs with `--yjit`**, its recommended production setting. Other interpreters run with
  their defaults.
- **Peak memory** is the maximum resident set size of one bench-size run under
  `/usr/bin/time -l`. **Artifact size** is the size of the built executable, jar or dll.
  **Lines of code** count non-blank lines that are not only a comment, without manifests.
- Builds use each language's release defaults, and runs use the deployable form, never a build
  tool's run command. The runner measures one thing at a time, and nothing else should run.
- **Comparisons.** The summary gives each language's geometric mean of its per-benchmark ratio
  to Rust. Rows marked `comparable = false` are shown but left out of the means and of the
  "vs fastest" baseline, and the library variants get their own table.

### Cheby's two rows

Cheby has two rows on the same programs, `benchmarks/<bench>/cheby/`. They differ in how the program
is run and in the build profile. Each has its own build cache under `build/`, through `CHEBY_CACHE`,
so a measurement never touches the machine's cache.

- **Cheby (AOT)**, id `cheby-aot`, is `cheby build --release`. Its run time is the executable, its
  artifact size is the executable, and its compile time is a release build from a cache that holds
  the standard library and none of the program. This is the row to compare with the other languages,
  which all build with their release defaults.
- **Cheby (JIT, whole process)**, id `cheby`, is `cheby run` as a developer types it: the debug
  profile, with the program's code in the cache. Its run time is the whole process: start-up,
  loading the cached code and the program. It has no compile time of its own, so it shows none and
  is left out of the compile means.

**The release profile.** Cheby gained `--release` on 2026-11-22. A release build calls functions
directly, runs Cranelift's optimizer, inlines small functions across modules and from the standard
library, and makes its own copies of generic functions for the dictionaries and callbacks it passes
them. The debug profile does none of that across modules, so that an edit rebuilds one module. Until
2026-11-22 both rows were debug builds.

**Why the cache is reset.** `cheby build` caches each module's compiled code, so a rebuild that only
removes the executable compiles nothing. `clean` runs `runner/cheby-cache.sh`, which restores a seed
that holds std in both profiles, as other languages keep their compiled standard library. Two
untimed builds of `runner/cheby-seed/`, a program that reaches every std module the benchmarks use,
fill the seed once per `cheby` binary. A timed build compiles the program and links it. Most of its
time is the link.

**Why the JIT has no estimate any more.** Until M3 the runner estimated compile time as a size-0 run
and run time as a bench-size run minus that. `cheby run` now loads cached code, so a warm size-0 run
compiles nothing, and that estimate would be a cache load.

For `compile_large`, the JIT row is one cold `cheby run` of the generated project from the same
seed, and the AOT row is one `cheby build --release`. `cheby check` is timed from the seed too, on
the JIT row, and reported as front-end time.

## Cheby's strengths and weaknesses

_This section and the per-benchmark notes analyse the Cheby rows of 2026-11-22, measured at commit
`7a586d82`. The tables in Results are newer: Cheby was measured again on 2026-11-24 at commit
`6341ff2b`, after a round of optimization that the analysis below asked for, and the AOT row is now
a release build. Where the two differ, the tables are right. The other languages' rows are from
2026-10-19 on the same machine._

**What changed by 2026-11-24.** Against Rust, Cheby's executables now take 3.84× on the CPU group,
7.15× on the data group and 4.85× on both together, where the analysis below quotes 9.68×, 13.1× and
10.8×. That puts Cheby ahead of Clojure (5.13×) and Koka (5.70×) on CPU and data together, where it
was level with the BEAM languages. `cheby run`, still the debug profile, stands at 4.31×, 7.86× and
5.40×. Median run times:

| Benchmark        | AOT, 11-22 | AOT, 11-24 | `cheby run`, 11-22 | `cheby run`, 11-24 |
| ---------------- | ---------: | ---------: | -----------------: | -----------------: |
| `binary_trees`   |     1.06 s |     875 ms |             1.04 s |             894 ms |
| `nbody`          |    27.24 s |    12.70 s |            28.20 s |            13.74 s |
| `spectral_norm`  |    21.48 s |     5.23 s |            21.55 s |             5.65 s |
| `mandelbrot`     |     1.67 s |     958 ms |             1.67 s |             964 ms |
| `fannkuch_redux` |     3.74 s |     680 ms |             3.56 s |             1.01 s |
| `word_freq`      |     2.07 s |     1.65 s |             2.13 s |             1.80 s |
| `json_roundtrip` |     3.76 s |     2.66 s |             3.87 s |             2.70 s |
| `lru_cache`      |    25.75 s |     7.41 s |            26.48 s |             8.94 s |
| `ping_pong`      |      57 ms |      56 ms |              64 ms |              61 ms |
| `spawn_many`     |      76 ms |      52 ms |              84 ms |              60 ms |
| `prime_sieve`    |      19 ms |      20 ms |              26 ms |              26 ms |

Most of the costs that the weaknesses below name are gone or smaller: the `Some` of every
`list::get`, the boxed result of `float::from_int`, the list pattern step that called the runtime,
the full call per loop iteration, the sorted tree inside `ordered_map`, and the module constant that
doubled a cold build. `json_roundtrip`'s parser no longer calls the runtime for each byte it reads;
the tree of values it builds and the field lookup over it remain. `docs/perf/optimization-log.md` in
the Cheby repository lists each change with its measurement, and what is still open.

On run time, Cheby's executables are 9.68× slower than Rust on the CPU group (5 benchmarks), 13.1×
on the data group (3) and 10.8× on both together (8). These are the Summary's geometric means.
`cheby run` is within a few percent of them (9.62×, 13.5× and 10.9×), because it loads the same
compiled code. On CPU, Gleam (10.1×), Ruby (17.0×) and Python (38.2×) are slower. On data, Cheby is
level with Clojure (13.0×) and ahead of Koka (17.8×), Elixir (18.7×), Erlang (19.9×) and Gleam
(27.6×). The per-benchmark notes trace most of the gap to the current compiler, runtime and standard
library, and a smaller part to the language's design.

The October JIT stood at 14.5×, 39.5× and 21.1×. Four benchmarks moved most: `json_roundtrip` from
49.1 s to 3.76 s, `spectral_norm` from 52.6 s to 21.5 s, `nbody` from 44.0 s to 27.2 s and
`word_freq` from 3.58 s to 2.07 s.

On the concurrency group, Cheby's executables need 0.07× the time of Rust's standard row, which uses
OS threads. Go (0.05×) and the Rust tokio variant (0.06×) are ahead. Against tokio alone, Cheby
needs 1.18× the time: 1.11× on `ping_pong`, 2.62× on `spawn_many` and 0.56× on `prime_sieve`.

`cheby build` takes 0.34× the time of Rust's cold build over 12 benchmarks. Only TypeScript (0.18×)
is lower. The build is unoptimised and starts with the standard library already compiled.

Strengths:

- **Cheap fibers and channels.** `ping_pong` runs in 57 ms, second of the 23 comparable rows. Only
  the rust-tokio variant (51 ms) is faster. Go takes 63 ms and Rust's OS threads 677 ms. A handoff
  stays on one worker thread and never enters the kernel: the whole run spent 1 ms there.
  `prime_sieve` (19 ms) is the fastest row, level with Go within noise. `spawn_many` (76 ms) is
  seventh of 23. M:N fibers are a design choice. The one allocation per message that remains is
  current implementation.
- **Fast builds and a fast start.** `cheby build` compiles `hello_world` in 55 ms and the 200-module
  `compile_large` project in 716 ms, where Rust's clean release build takes 2.29× as long. This
  compares unoptimised code against release builds: Cheby's release profile comes with M6. The
  executable starts in 1.5 ms, like the other AOT languages (1.1 ms to 1.7 ms). `cheby run` prints
  `hello_world` in 6.1 ms, faster than every VM and interpreter: Python takes 18 ms, Java 22 ms and
  the BEAM languages 87 ms to 105 ms.
- **Allocation-heavy code runs near the malloc/free languages.** `binary_trees` takes 1.07× Rust,
  ahead of C++ (1.12 s), Odin (1.26 s) and Swift (1.66 s). There is one heap object per node, freed
  by its count (D-005), and `check` borrows its tree, so the walk touches no counts.
- **Unique values are updated in place.** In `fannkuch_redux`, 137.7 million `list::set` calls
  update in place and 3.27 million copy. In `nbody` every record update reuses its record: 770
  million reuses and no miss. In `lru_cache` and `word_freq` the counters report no copied map
  update. This is Perceus reuse, part of the language's design (D-005, spec §9.3).
- **Low peak memory.** A Cheby executable's floor is 3.5 MB (`hello_world`), inside the 1.6 MB to
  4.2 MB of the other AOT languages. `lru_cache` peaks at 18.2 MB, against about 320 MB for Erlang
  and Elixir and 2.1 GB for Clojure. `word_freq` peaks at 230 MB, against 1.8 GB to 2.8 GB for the
  BEAM rows. `cheby run` adds the compiler and the JIT: its floor is 16.4 MB.

Weaknesses:

- **`List` is the only general sequence type, and list code pays for it.** `fannkuch_redux` is last
  at 24× Rust, `spectral_norm` is 18th of 21 at 27× and `nbody` 18th at 53×. No arrays and no
  mutation are design (D-017, D-039). The rest is current implementation. Every `list::get`
  allocates a `Some`, and every indexed read or write is a runtime call into the tree. Building a
  list with `[x, ..xs]` allocates tree nodes, which costs a third of `spawn_many`'s run. One cost
  has gone since October: a `[x, ..rest]` pattern step was three runtime calls, and is now inline or
  one call (D-1757 to D-1760).
- **Float code pays for the calling convention.** A function returns one uniform word (D-453), so a
  returned `Float` is boxed. `float::from_int` allocates on every call: `spectral_norm` makes 1.21
  billion allocations, one per matrix entry. A local-function loop is several times slower (the
  `mandelbrot` SPEC), so the programs use top-level loops. Even then, `mandelbrot` (2.34× Rust) runs
  a full call per iteration through the function's slot (D-015, D-043). The notes class the boxed
  `from_int` result and the call overhead as current implementation.
- **The runtime's own allocation and free path is heavy.** In `binary_trees`, Koka, also Perceus
  over mimalloc, is 2.67× faster. The profile puts 44% of Cheby's samples in the runtime's
  allocation and free code and 6% in mimalloc. The same code takes 35% to 42% of `nbody`,
  `spectral_norm` and `json_roundtrip`. That is current implementation.
- **Persistent maps cost more work per operation, and std lacks some shortcuts.** `lru_cache` is 39×
  Rust, among the other rows that keep two persistent maps, while Koka is 1.84× faster. With no
  move-to-end, a hit is four hash operations and two tree updates. The tree is Cheby code and takes
  most of the run. It compares keys through a dictionary until specialization, planned for M6
  (D-251). `word_freq` (5.9× Rust) copies most of the text twice when it splits, and calls back into
  a closure for every word. No mutable hash table or linked list is design (D-017). The rest is
  current std and runtime.
- **`std::json` is ten times slower than Rust's library.** `json_roundtrip` is 17th of 21 at 9.7×
  Rust, behind OCaml (Cheby 1.09×) and ahead of Erlang. It was last in October, at 127×: the parser
  now scans bytes where it walked a list of code points. Allocation (35% of samples) and compiled
  Cheby code (33%) share the time that is left. This is the current standard library, not a limit of
  the language.
- **A module constant is slow to compile.** Each constant is evaluated in a JIT module of its own
  and cached on its own (D-977 to D-979), and every use reads it through a slot. In `compile_large`,
  replacing the 200 modules' one-literal constant with the literal cut a cold `cheby build` from 757
  ms to 346 ms.

Caveats:

- Cheby has two rows on the same programs. This section quotes the executable unless it names `cheby
  run`. `cheby run`'s time is a whole process with the program's code already in the cache, so that
  row has no compile time.
- The concurrency group compares task runtimes. Rust's standard row uses OS threads, so the 0.07×
  ratio measures Cheby's fibers against kernel threads. The Rust tokio variant is the closer
  comparison. The Summary never averages run time over all groups for this reason.
- Each row is one session on one machine. Runs over 5 s get 3 timings, which covers Cheby's `nbody`,
  `spectral_norm` and `lru_cache`. Python's `spectral_norm`, over 60 s, was timed once (n=1).
- The profile shares in the notes come from one sampling run of each executable at the bench size.
  The three concurrency runs are too short to sample, so their notes cite Cheby's own longer fiber
  benchmarks.
- Koka's concurrency rows are not comparable and are left out of the means: its `std/async` is
  cooperative, single-threaded and has no dynamic spawn.
- Some rows do different work: the JSON libraries differ, Koka writes its own parser, and the
  `compile_large` rows range from in-memory bytecode to optimised, linked release builds.

## Results

<!-- results:start -->
_Measured on Apple M3, macOS 27.0 (26A428), Cheby rows 2026-11-24, other languages 2026-10-19. Full tables: [RESULTS.md](RESULTS.md); charts: [report/index.html](report/index.html)._

| Language                   | Kind        | CPU run vs Rust | Data run vs Rust | Concurrency run vs Rust | CPU + data run vs Rust | Compile vs Rust (cold) |
| -------------------------- | ----------- | --------------: | ---------------: | ----------------------: | ---------------------: | ---------------------: |
| Cheby (JIT, whole process) | jit         |       4.31× (5) |        7.86× (3) |               0.07× (3) |              5.40× (8) |                      – |
| Cheby (AOT)                | aot         |       3.84× (5) |        7.15× (3) |               0.06× (3) |              4.85× (8) |             0.33× (12) |
| Gleam                      | beam        |       10.1× (5) |        27.6× (3) |               0.35× (3) |              14.7× (8) |             1.05× (12) |
| Rust                       | aot         |       1.00× (5) |        1.00× (3) |               1.00× (3) |              1.00× (8) |             1.00× (12) |
| Go                         | aot         |       1.08× (5) |        1.60× (3) |               0.05× (3) |              1.25× (8) |             1.22× (12) |
| Zig                        | aot         |       0.89× (5) |        1.38× (3) |               1.07× (3) |              1.05× (8) |             28.6× (12) |
| Odin                       | aot         |       1.16× (5) |        2.73× (3) |               1.27× (3) |              1.60× (8) |             6.44× (12) |
| C++                        | aot         |       1.15× (5) |        2.12× (3) |               1.84× (3) |              1.45× (8) |             2.11× (12) |
| Erlang                     | beam        |       7.69× (5) |        19.9× (3) |               0.31× (3) |              11.0× (8) |             0.73× (12) |
| Python                     | interpreter |       38.2× (5) |        6.76× (3) |               1.86× (3) |              19.9× (8) |                      – |
| Java                       | jvm         |       0.90× (5) |        2.85× (3) |               0.30× (3) |              1.39× (8) |             1.25× (12) |
| TypeScript                 | jsvm        |       1.23× (5) |        3.59× (3) |               0.14× (3) |              1.84× (8) |             0.18× (12) |
| Swift                      | aot         |       1.33× (5) |        3.09× (3) |               0.39× (3) |              1.82× (8) |             2.06× (12) |
| C#                         | clr         |       1.17× (5) |        2.92× (3) |               0.33× (3) |              1.65× (8) |             6.33× (12) |
| Elixir                     | beam        |       8.84× (5) |        18.7× (3) |               0.40× (3) |              11.7× (8) |             1.73× (12) |
| Scala                      | jvm         |       1.03× (5) |        3.82× (3) |               0.47× (3) |              1.68× (8) |             6.92× (12) |
| Clojure                    | jvm         |       2.94× (5) |        13.0× (3) |               0.74× (3) |              5.13× (8) |             2.16× (12) |
| Koka                       | aot         |       2.88× (5) |        17.8× (3) |                       – |              5.70× (8) |              4.52× (9) |
| OCaml                      | aot         |       1.24× (5) |        6.18× (3) |               3.02× (3) |              2.27× (8) |             0.99× (12) |
| Nim                        | aot         |       1.23× (5) |        2.31× (3) |               1.25× (3) |              1.56× (8) |             2.43× (12) |
| Ruby                       | interpreter |       17.0× (5) |        4.28× (3) |               2.98× (3) |              10.1× (8) |                      – |

Geometric mean of the per-benchmark ratio to Rust, with the number of benchmarks in parentheses. Below 1× is faster than Rust. Run time is averaged per group (CPU, data, concurrency, and CPU and data together) and never over all three: the concurrency benchmarks compare task runtimes, often lightweight tasks against Rust's OS threads, and one mean over everything would let them hide the CPU and data results. Compile time covers every benchmark with a compile step and is the cold compile (no build server; Scala's and C#'s warm compile is in the per-benchmark tables). Rows marked not comparable are left out: Koka (ping_pong, spawn_many, prime_sieve).

- Koka: cooperative single-threaded std/async (no dynamic spawn); measured but not comparable, and left out of the geometric means

Library variants (a well-known concurrency library instead of the standard one) cover only the benchmarks listed, so they are kept out of the table above:

| Variant              | Benchmarks                         | Run time vs Rust | Run time vs base language |
| -------------------- | ---------------------------------- | ---------------: | ------------------------: |
| Rust (tokio)         | ping_pong, spawn_many, prime_sieve |        0.06× (3) |         0.06× (3) vs Rust |
| Clojure (core.async) | ping_pong, spawn_many, prime_sieve |        1.62× (3) |      2.19× (3) vs Clojure |
| OCaml (Eio)          | ping_pong, spawn_many, prime_sieve |        0.52× (3) |        0.17× (3) vs OCaml |
<!-- results:end -->
