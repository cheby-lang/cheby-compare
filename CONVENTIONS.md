# Conventions

The rules every implementation, spec and tool in this repository follows. They exist so that the
numbers compare like with like. When a rule and an implementation disagree, the implementation is
wrong.

## Languages

Twenty languages, each with an id used in paths and results:

| Id           | Language   | Kind        | Toolchain (2026-10)               |
| ------------ | ---------- | ----------- | --------------------------------- |
| `cheby`      | Cheby      | JIT         | `../cheby/target/release/cheby`   |
| `gleam`      | Gleam      | BEAM        | gleam 1.19, Erlang/OTP 29         |
| `rust`       | Rust       | AOT         | rustc 1.99                        |
| `go`         | Go         | AOT         | go 1.27                           |
| `zig`        | Zig        | AOT         | zig 0.17                          |
| `odin`       | Odin       | AOT         | odin dev-2026-10                  |
| `cpp`        | C++        | AOT         | Apple clang 21                    |
| `erlang`     | Erlang     | BEAM        | Erlang/OTP 29                     |
| `python`     | Python     | interpreter | CPython 3.15                      |
| `java`       | Java       | JVM         | OpenJDK 27                        |
| `typescript` | TypeScript | JS VM       | tsc 7.0, node 24                  |
| `swift`      | Swift      | AOT         | Swift 6.4                         |
| `csharp`     | C#         | CLR         | .NET SDK 10.0                     |
| `elixir`     | Elixir     | BEAM        | Elixir 1.20, Erlang/OTP 29        |
| `scala`      | Scala      | JVM         | Scala 3.10 (scala-cli), OpenJDK 27 |
| `clojure`    | Clojure    | JVM         | Clojure 1.12, OpenJDK 27          |
| `koka`       | Koka       | AOT         | koka 3.2                          |
| `ocaml`      | OCaml      | AOT         | OCaml 5.5                         |
| `nim`        | Nim        | AOT         | nim 2.2                           |
| `ruby`       | Ruby       | interpreter | Ruby 4.0                          |

The JDK lives at `/opt/homebrew/opt/openjdk/bin` and is not on the default `PATH`. Language configs
put it there through `env`. `DOTNET_ROOT` is `/opt/homebrew/opt/dotnet/libexec`.

**Library variants.** The concurrency benchmarks also get a second row where a well-known library
changes the picture: `rust-tokio`, `clojure-coreasync` and `ocaml-eio`. A variant is a separate id
with its own `langs/<id>.toml` and exists only for `ping_pong`, `spawn_many` and `prime_sieve`.
Gleam has no concurrency in its standard library, so its main row uses `gleam_erlang` and
`gleam_otp`, and it gets no variant.

## Benchmarks

| Id               | Group          | What it shows                                               |
| ---------------- | -------------- | ----------------------------------------------------------- |
| `binary_trees`   | CPU            | allocation and freeing of many small nodes                  |
| `nbody`          | CPU            | floating point on a few records, many steps                 |
| `spectral_norm`  | CPU            | floating point over vectors, O(n²) per step                 |
| `mandelbrot`     | CPU            | tight float loops, no allocation                            |
| `fannkuch_redux` | CPU            | in-place permutation of a small array                       |
| `word_freq`      | data           | reading a file, splitting, hash map counting, sorting       |
| `json_roundtrip` | data           | parsing, walking and serializing a JSON document            |
| `lru_cache`      | data           | an LRU cache under a pseudo-random access stream            |
| `ping_pong`      | concurrency    | message passing between two lightweight tasks               |
| `spawn_many`     | concurrency    | spawning and joining many short tasks                       |
| `prime_sieve`    | concurrency    | a pipeline of filter tasks connected by channels            |
| `hello_world`    | compile speed  | the smallest program: cold compile time and startup         |
| `compile_large`  | compile speed  | a generated project of many modules: compile-time scaling   |

## Layout

```text
benchmarks/<bench>/
  SPEC.md              the algorithm, the arguments, the exact output, the sizes
  sizes.toml           the argument lists for each size (below)
  expected/<size>.out  the exact stdout for each size
  <lang>/              one implementation: sources, a build manifest if the language wants one,
                       and optionally impl.toml
langs/<lang>.toml      how to build, clean, run and measure a language
inputs/gen.py          deterministic generator for input files, written to inputs/data/
runner/                run.py (build, verify, measure), report.py, loc.py
results/               measured JSON, one file per run
RESULTS.md             generated tables
report/index.html      generated charts
```

`compile_large` differs: `benchmarks/compile_large/<lang>/gen.py` writes a project of a given size
into a directory, and the runner builds that project (see its SPEC.md).

## The program contract

- A program reads its arguments from the command line, writes its result to stdout, and exits 0.
  It reads no environment variable and no file except one named in its arguments.
- **Size 0 is valid** and must run almost instantly with the same code path. Cheby's compile time
  is measured as a run at size 0 (below), so size 0 must still load and compile the whole program.
- Output is deterministic and byte-identical across languages: the same lines, `\n` endings, no
  trailing spaces.
- **No float formatting.** Languages format floats differently, and Cheby has no fixed-decimal
  formatting. Every float in the output is printed as an integer: `round(x * 10^k)`, rounding half
  away from zero, with `k` fixed by the spec. Integers print in plain decimal, with no separators.
- Pseudo-random data comes from the generator the spec defines, usually a 64-bit LCG or xorshift
  with wrapping arithmetic. Never use a language's own random module.

## Fairness rules

- **Same algorithm.** Every implementation follows SPEC.md step by step: the same data layout
  choices where the spec fixes them, the same number of iterations, no precomputed answers, no
  memoising across iterations unless the spec says so.
- **Idiomatic.** Write the program the way a fluent developer would in that language, as a single
  file or the language's smallest normal project. No SIMD intrinsics, no `unsafe` or raw pointers
  beyond what the language's normal style uses, no hand-rolled allocators, no inline assembly.
- **Parallelism.** CPU and data benchmarks are single-threaded. Concurrency benchmarks use the
  language's idiomatic concurrency primitive, listed in each spec. Every runtime keeps its default
  thread count.
- **Standard library first.** A third-party library is allowed only for JSON when the standard
  library has none (`serde_json`, `nlohmann/json`, Jackson, `ujson`, `clojure.data.json`, `yojson`,
  `gleam_json`; Koka writes its own parser), and for the library variants above. Name every library
  in `impl.toml` under `libs`.
- **Optimised builds**, with the flags in `langs/<lang>.toml`: release mode, the language's default
  optimisation level for release (C++ uses `-O3`, CMake's Release default), no `-march=native`,
  no LTO unless it is the release default, no profile-guided optimisation. Interpreters run with
  their default settings, except Ruby, which runs with `--yjit`, its recommended production setting.
- **Deployable form.** Run what a developer would deploy: the compiled executable, the JVM on a jar
  or class directory with plain `java`, `node` on the emitted JavaScript, `dotnet` on the published
  dll, `erl` on the compiled beams. Never time a build tool's run command (`cargo run`,
  `scala-cli run`, `gleam run`, `mix run`, `dotnet run`), which adds its own start-up.

## `langs/<lang>.toml`

```toml
id = "rust"
name = "Rust"
kind = "aot"                         # aot | jit | jvm | clr | beam | jsvm | interpreter
version = "rustc --version"          # its first line goes into the results
comment = "//"                       # line-comment prefix, for lines of code
extensions = [".rs"]                 # source files counted for lines of code
env = {}                             # extra environment for every command

# Every command runs in the implementation directory, benchmarks/<bench>/<lang>/, through sh -c.
# Placeholders: {build} is an absolute, per-implementation build directory under build/,
# {args} the size's arguments, {cheby} the cheby binary, {root} the repository root.
build = "cargo build --release --quiet --target-dir {build}"
clean = "rm -rf {build}/release/main {build}/release/deps/main-*"   # keep third-party builds
run = "{build}/release/main {args}"
artifact = "{build}/release/main"    # optional, for the artifact size
```

`build` empty means the language has no compile step (Python, Ruby). `clean` removes the program's
own outputs but keeps fetched and compiled third-party dependencies, so the compile time is the
time to compile this program, not its libraries. The same holds for the standard library: where a
toolchain can reuse a compiled standard library (Go's cache, Koka's and Nim's object caches,
Swift's module cache, the precompiled libraries of Rust, OCaml and the BEAM), `clean` keeps it,
after an untimed warm-up build if needed. Zig and Odin compile the program and its standard
library as one unit and cannot reuse it, so their compile time includes it. An implementation may override any key, and add
`libs = [...]` and `notes = "..."`, in `benchmarks/<bench>/<lang>/impl.toml`.

## `sizes.toml`

```toml
zero = ["0"]
test = ["10"]
bench = ["21"]
```

Each value is the argument list for that size. `{data}` stands for `inputs/data`, for benchmarks
that read a generated file. `test` is small enough to check every language in about a second.
`bench` makes Rust and C++ take roughly 0.5 to 1 second.

## Measurement

- **Runs** use hyperfine: one warm-up and ten runs, three runs when one run takes over five seconds,
  and a single run when it takes over sixty. A run over 300 seconds is recorded as a timeout. The
  median is reported, with min and max.
- **Compile** time is hyperfine over `build`, with `clean` as `--prepare`, five runs.
- **Warm compile** is a second compile time, only for languages whose normal workflow keeps a build
  server running: Scala (Bloop) and C# (the .NET build server and shared compiler). Their config
  sets `warm_start` (start the server), optionally `build_warm` (the build command with the server
  allowed; defaults to `build`) and `warm_stop`. The runner starts the server, does three warm-up
  builds, then times five builds after `clean`. The cold compile, with no server, stays the main
  number, since Cheby and most languages have no server.
- **Peak memory** is one run under `/usr/bin/time -l`, its maximum resident set size.
- **Artifact size** is the size of `artifact`, when the config names one.
- **Lines of code** count non-blank lines of the implementation's sources that are not only a comment.
  Inline tests (Cheby `test` blocks, Zig `test` blocks, Rust `#[cfg(test)]` modules) and docstrings
  (Python docstrings, Elixir `@doc` and `@moduledoc`) are not counted.
- **Start-up** is the median run time at size 0.
- **Output** is checked against `expected/` before anything is timed. A wrong output is never timed.
- **Cheby** compiles and runs in one step until its milestone M3 adds AOT output. Its compile time is
  the median run at size 0 of the same program, whose JIT compiles every function that `main`
  reaches, eagerly, before `main` runs (D-510; lazy compilation arrives in M3, D-254). Size 0 must
  take the same code path, so that this is all of the program. Its run time is the median run at the bench
  size minus that. Both are marked as estimates in the reports. `cheby check` time is reported too,
  as front-end time. When M3 lands, Cheby moves to `cheby build` like the AOT languages.
- Nothing else runs while measuring: the runner measures one thing at a time.
