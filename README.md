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
| `cheby`             | Cheby                | JIT         | compile and run times are an estimated split, see below |
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
row: tokio for Rust, core.async for Clojure and Eio for OCaml. A variant appears only in those
three benchmarks. The report labels it with its library, for example "Rust (tokio)", and gives it
its own summary table, because a geometric mean over three benchmarks does not compare with the
per-language means over all of them. Gleam has no concurrency in its standard library, so its
main row uses `gleam_erlang` and `gleam_otp`, and it has no variant.

### Koka

- **`compile_large` at the bench size is a known build failure.** Koka's generated C header for
  each module includes the header of every module it imports, so the chain of 200 modules nests
  200 headers deep, and Apple clang stops at its fixed include-depth limit of 200 ("#include
  nested too deeply"; no flag raises it). Sizes `zero` and `test` build, and so do 199 modules.
  The report shows the reason, from `known_failure` in the implementation's `impl.toml`, instead
  of the raw error.
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
  Eio), so the number is the time to compile the program, not its libraries.
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

### Cheby's estimated split

Until its milestone M3 adds AOT output, Cheby only has a JIT, and `cheby run` type-checks,
compiles and runs in one process. Its compile and run times cannot be timed apart, so they are
**estimated**:

- **Compile ≈** the median run at size 0 **of the same program**. The JIT compiles every function
  that `main` reaches before `main` starts (D-510), which in these programs is all of the
  benchmark's code, so this run compiles all of it, not a hello-world-sized amount, and then does
  almost no work.
- **Run ≈** the median run at the bench size minus that estimate.
- `cheby check` is timed too and reported as front-end time.

Every report marks these numbers: rows say "JIT, estimated split", values carry ≈, and the
summary also gives Cheby's whole-process ratio (compile + run) next to the estimate. Known
limits of the split:

- The size-0 run also contains process start-up and runtime initialisation, so the compile
  estimate is slightly high and the run estimate slightly low compared with the other
  languages, whose run time includes their start-up.
- The run estimate is the difference of two noisy medians. On short benchmarks its relative
  error is large; it is clamped at 0 and flagged when the difference is negative.
- The split relies on eager compilation. If `cheby run` starts compiling lazily (planned with
  M3's cached code, D-254), a size-0 run would skip code that only the real workload reaches,
  and compile work would move into the run estimate. Cheby moves to `cheby build` with M3, which
  removes the estimate. An exact in-process split would need a timing option in the compiler,
  which would need its own decision-log entry there.
- For `compile_large`, Cheby's number is a `cheby run` of the generated project: compile plus a
  trivial `main`.

## Cheby's strengths and weaknesses

On run time, Cheby is 14.5× slower than Rust on the CPU group (5 benchmarks), 39.5× on the data
group (3) and 21.1× on both together (8). These are the Summary's geometric means. On CPU, only
Ruby (17.0×) and Python (38.2×) are slower. On data, Cheby is the slowest row, behind Gleam
(27.6×) and Erlang (19.9×). The per-benchmark notes trace most of the gap to the current compiler,
runtime and standard library, and a smaller part to the language's design.

On the concurrency group, Cheby needs 0.08× the time of Rust's standard row, which uses OS
threads. Go (0.05×) and the Rust tokio variant (0.06×) are ahead of it. Against tokio alone,
Cheby needs 1.34× the time: 1.39× on `ping_pong`, 3.05× on `spawn_many` and 0.57× on
`prime_sieve`. Cheby's compile time is 0.06× Rust's cold build over 12 benchmarks, but that
number is a size-0 `cheby run`: it writes no file, links nothing and generates unoptimised code.
As a whole process, `hello_world` takes 9.9 ms, against 1.1 ms to 1.7 ms for the AOT languages.

Strengths:

- **Cheap fibers and channels.** `ping_pong` runs in ≈ 71 ms, second of the 19 comparable
  languages behind Go (63 ms), and 9.51× faster than Rust's OS threads. The rust-tokio variant
  (51 ms) is faster too. A handoff stays on one worker thread and never enters the kernel: the
  whole run spent 8.3 ms in the kernel, about the 8.1 ms of a size-0 run. `prime_sieve` (≈ 20 ms)
  ties Go, and `spawn_many` (≈ 88 ms) is fifth of 19, in the lightweight-task band, with the
  rust-tokio and OCaml Eio variants also ahead. M:N fibers are a design choice. The two
  allocations per message that remain are current implementation.
- **Short time from source to output.** `hello_world` (9.9 ms) beats every VM and interpreter:
  Python takes 18 ms, Java 22 ms and the BEAM languages 87 ms to 105 ms. `compile_large` runs a
  200-module project in ≈ 242 ms, 4th of 19, while Rust's clean release build takes 6.79× as long.
  This compares unoptimised in-memory code against release builds, and M3 changes both columns.
- **Allocation-heavy code runs near the malloc/free languages.** `binary_trees` takes 1.34× Rust,
  just behind C++ (1.12 s) and Odin (1.26 s) and ahead of Swift (1.66 s). There is one heap object
  per node, freed by its count (D-005), and `check` borrows its tree, so the walk touches no
  counts.
- **Unique values are updated in place.** `fannkuch_redux`'s `list::set` updates in place almost
  every time. In `lru_cache` the counters report no copied map update, and `word_freq`'s
  `map::upsert` copies no path. This is Perceus reuse, part of the language's design (D-005,
  spec §9.3).
- **Lower peak memory than the BEAM and the JVM.** `lru_cache` peaks at 39.8 MB, against about
  320 MB for Erlang and Elixir and 2.1 GB for Clojure. `word_freq` peaks at 257 MB, against 1.8 GB
  to 2.8 GB for the BEAM rows. Every `cheby run` has an 18.9 MB floor, `hello_world`'s peak, most
  of it the front end checking std, so Cheby stays above Rust everywhere.

Weaknesses:

- **`List` is the only general sequence type, and list code pays for it.** `fannkuch_redux` is last at 29.2×
  Rust, `spectral_norm` is 19th at 65.5× and `nbody` 19th at 85.6×. No arrays and no mutation are
  design (D-017, D-039). Most of the cost is current implementation: each `[x, ..rest]` step is
  three out-of-line runtime calls, every `list::get` allocates a `Some`, and a record read from a
  list is often still shared, so its update cannot reuse it. `nbody` over a hand-made cons type ran
  several times faster in a scratch test.
- **Float code pays for the calling convention.** A function returns one uniform word (D-453), so
  a returned `Float` is boxed. `float::from_int` allocates on every call, and carrying
  `spectral_norm`'s indices as `Float` cut its run time by more than half in a scratch test. A
  local-function loop is several times slower (the `mandelbrot` SPEC), so the programs use
  top-level loops. Even then, `mandelbrot` (2.97× Rust) runs a full call per iteration through the
  JIT's indirection slot (D-015, D-043). The notes class the boxed `from_int` result and the call
  overhead as current implementation.
- **`std::json` is slow.** `json_roundtrip` is last at 127× Rust, 3.96× behind Gleam. The parser,
  written in Cheby, turns the text into a list of code points and walks it with list patterns, and
  the decoders and the writer allocate more on the success path. This is the current standard
  library, not a limit of the language.
- **Persistent maps cost more work per operation, and std lacks some shortcuts.** `lru_cache` is
  47× Rust, level with Erlang and Elixir, while Koka is 2.23× faster. With no move-to-end, a hit
  is three hash lookups, a hash remove, a hash insert and two tree updates. The tree compares keys
  through a dictionary until specialization, planned for M6 (D-251). `word_freq` (10.3×) splits by
  hand, since `std::string` has no whitespace splitter, and copies most of the text twice. No
  mutable hash table or linked list is design (D-017). The rest is current std and runtime.
- **The runtime's own allocation and free path is heavy.** In `binary_trees`, Koka, also Perceus
  over mimalloc, is 3.35× faster. Most of Cheby's samples are in the runtime's per-object
  bookkeeping, not in mimalloc. That is current implementation.
- **Start-up is mostly checking the standard library.** `cheby check` takes 8.0 ms of
  `hello_world`'s 9.1 ms start-up. About 2 ms to 3 ms of that is process launch, and nearly all
  the rest is parsing and checking the 23 std modules this program pulls in, most of them implicit
  dependencies of every module (D-447). M3 is to ship
  std precompiled (D-256), and `cheby build` will remove the front end from start-up.

Caveats:

- Cheby's compile and run times are an estimated split (see above). It is negligible for the long
  benchmarks and means nothing for `hello_world`. On the concurrency rows it matters: the
  subtracted size-0 run is 11% (`spawn_many`) to 36% (`prime_sieve`) of the whole process.
- The concurrency group compares task runtimes. Rust's standard row uses OS threads, so the 0.08×
  ratio measures Cheby's fibers against kernel threads. The Rust tokio variant is the closer
  comparison. The Summary never averages run time over all groups for this reason.
- Each row is one session on one machine. Runs over 5 s get 3 timings, which covers Cheby's
  `nbody`, `spectral_norm`, `json_roundtrip` and `lru_cache`. Python's `spectral_norm`, over 60 s,
  was timed once (n=1).
- Koka's concurrency rows are not comparable and are left out of the means: its `std/async` is
  cooperative, single-threaded and has no dynamic spawn.
- Some rows do different work: the JSON libraries differ, Koka writes its own parser, and the
  `compile_large` rows range from in-memory bytecode to optimised, linked release builds.

## Results

<!-- results:start -->
_Measured on Apple M3, macOS 27.0 (26A428), 2026-10-19. Full tables: [RESULTS.md](RESULTS.md); charts: [report/index.html](report/index.html)._

| Language                             | Kind        | CPU run vs Rust | Data run vs Rust | Concurrency run vs Rust | CPU + data run vs Rust | Compile vs Rust (cold) |
| ------------------------------------ | ----------- | --------------: | ---------------: | ----------------------: | ---------------------: | ---------------------: |
| Cheby (JIT, estimated split)         | jit         |       14.5× (5) |        39.5× (3) |               0.08× (3) |              21.1× (8) |             0.06× (12) |
| Cheby (whole process: compile + run) | jit         |       14.6× (5) |        39.6× (3) |               0.09× (3) |              21.2× (8) |                      – |
| Gleam                                | beam        |       10.1× (5) |        27.6× (3) |               0.35× (3) |              14.7× (8) |             1.05× (12) |
| Rust                                 | aot         |       1.00× (5) |        1.00× (3) |               1.00× (3) |              1.00× (8) |             1.00× (12) |
| Go                                   | aot         |       1.08× (5) |        1.60× (3) |               0.05× (3) |              1.25× (8) |             1.22× (12) |
| Zig                                  | aot         |       0.89× (5) |        1.38× (3) |               1.07× (3) |              1.05× (8) |             28.6× (12) |
| Odin                                 | aot         |       1.16× (5) |        2.73× (3) |               1.27× (3) |              1.60× (8) |             6.44× (12) |
| C++                                  | aot         |       1.15× (5) |        2.12× (3) |               1.84× (3) |              1.45× (8) |             2.11× (12) |
| Erlang                               | beam        |       7.69× (5) |        19.9× (3) |               0.31× (3) |              11.0× (8) |             0.73× (12) |
| Python                               | interpreter |       38.2× (5) |        6.76× (3) |               1.86× (3) |              19.9× (8) |                      – |
| Java                                 | jvm         |       0.90× (5) |        2.85× (3) |               0.30× (3) |              1.39× (8) |             1.25× (12) |
| TypeScript                           | jsvm        |       1.23× (5) |        3.59× (3) |               0.14× (3) |              1.84× (8) |             0.18× (12) |
| Swift                                | aot         |       1.33× (5) |        3.09× (3) |               0.39× (3) |              1.82× (8) |             2.06× (12) |
| C#                                   | clr         |       1.17× (5) |        2.92× (3) |               0.33× (3) |              1.65× (8) |             6.33× (12) |
| Elixir                               | beam        |       8.84× (5) |        18.7× (3) |               0.40× (3) |              11.7× (8) |             1.73× (12) |
| Scala                                | jvm         |       1.03× (5) |        3.82× (3) |               0.47× (3) |              1.68× (8) |             6.92× (12) |
| Clojure                              | jvm         |       2.94× (5) |        13.0× (3) |               0.74× (3) |              5.13× (8) |             2.16× (12) |
| Koka                                 | aot         |       2.88× (5) |        17.8× (3) |                       – |              5.70× (8) |              4.52× (9) |
| OCaml                                | aot         |       1.24× (5) |        6.18× (3) |               3.02× (3) |              2.27× (8) |             0.99× (12) |
| Nim                                  | aot         |       1.23× (5) |        2.31× (3) |               1.25× (3) |              1.56× (8) |             2.43× (12) |
| Ruby                                 | interpreter |       17.0× (5) |        4.28× (3) |               2.98× (3) |              10.1× (8) |                      – |

Geometric mean of the per-benchmark ratio to Rust, with the number of benchmarks in parentheses. Below 1× is faster than Rust. Run time is averaged per group (CPU, data, concurrency, and CPU and data together) and never over all three: the concurrency benchmarks compare task runtimes, often lightweight tasks against Rust's OS threads, and one mean over everything would let them hide the CPU and data results. Compile time covers every benchmark with a compile step and is the cold compile (no build server; Scala's and C#'s warm compile is in the per-benchmark tables). Rows marked not comparable are left out: Koka (ping_pong, spawn_many, prime_sieve).

- Koka: cooperative single-threaded std/async (no dynamic spawn); measured but not comparable, and left out of the geometric means

Library variants (a well-known concurrency library instead of the standard one) cover only the benchmarks listed, so they are kept out of the table above:

| Variant              | Benchmarks                         | Run time vs Rust | Run time vs base language |
| -------------------- | ---------------------------------- | ---------------: | ------------------------: |
| Rust (tokio)         | ping_pong, spawn_many, prime_sieve |        0.06× (3) |         0.06× (3) vs Rust |
| Clojure (core.async) | ping_pong, spawn_many, prime_sieve |        1.62× (3) |      2.19× (3) vs Clojure |
| OCaml (Eio)          | ping_pong, spawn_many, prime_sieve |        0.52× (3) |        0.17× (3) vs OCaml |
<!-- results:end -->
