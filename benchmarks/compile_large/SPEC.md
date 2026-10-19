# compile_large

A generated project of `M` modules. It measures how compile time grows with the size of a
project.

## Purpose

Every language gets the same synthetic project: `M` source files, each with the same 20 small
functions, one record type and one sum type. The functions differ only in their integer
constants. A `main` calls into every module and prints one checksum. The program's own work is
tiny (about `20 * M` calls), so the measured time is the time to build or load the project.

It stresses the whole compiler pipeline on plain code: parsing, name resolution across many
files, type checking, pattern-match compilation and code generation for many small functions.
It does not stress generics, macros or heavy optimisation.

- AOT compilers with an optimising back end (Rust, C++, Swift, Zig) are expected to be the
  slowest per module. LLVM spends most of its time on many small functions.
- Go, OCaml and the JVM and CLR compilers are usually fast here. But each module imports the one
  before it, so a compiler that builds one module at a time in dependency order (Go, OCaml in
  release, Koka) never has two modules ready at once and runs serially. That comes from the
  project's shape, not from how the build is spelled (see Parallelism).
- Interpreters (Python, Ruby) parse, compile to bytecode and load every module on every timed
  run, with no bytecode cache (see Measurement). They are measured as a full run.
- For Cheby this is expected to be a strength. Its front end is built to compile-speed budgets
  (D-247) and its JIT uses Cranelift, a fast code generator that does little optimisation. Today
  `cheby run` compiles every function eagerly before `main` runs, so a run at size `M` pays the
  full code generation of all `20 * M` functions. It compiles in parallel: `-j` defaults to the
  available parallelism, so Cheby gets several cores where Python gets one (see Parallelism).
  Cached module code and lazy compilation (D-254) arrive in M3 and are not measured here.
  Cheby's number is an estimate (see Measurement).

## Arguments

`gen.py` takes two arguments: `M`, the number of modules (an integer, at least 1), and `outdir`.

```sh
python3 gen.py <M> <outdir>
```

It writes a complete, buildable project into `outdir`, creating it if needed. The output depends
only on `M`: the same `M` gives the same files, byte for byte. The generator writes the project
into `outdir` and nothing else. `sizes.toml` sets the runner's `gen` command to this argument
order.

The **generated program takes no arguments**, reads nothing and prints one line.

## Naming

- Module `i`, for `i = 0, 1, ..., M - 1`, is named `m` followed by `i` in four digits, zero
  padded: `m0000`, `m0001`, ..., `m0199`. `M` is at most 9999.
- One source file per module, named after the module (`m0007.rs`, `m0007.py`, `m0007.cheby`),
  plus the language's normal entry file (`main.rs`, `main.py`, `main.cheby`) and a manifest if
  the language needs one.
- Adapt the case to the language: `M0007` for a Java class or an Elixir module, `m0007` for a
  Go package. Function names may follow the language's case convention (`makeItem`,
  `make-item`).

## Constants

```text
P = 1000003                                     # the modulus

c(i, s) = ((i * 7919 + s * 104729) mod 10007) mod 97 + 2     # 2 <= c(i, s) <= 98
```

`c(i, s)` is the constant of slot `s` in module `i`. **The generator computes every constant and
writes it into the source as a plain integer literal.** The generated code never computes
`c(i, s)` itself. Below, `K[s]` stands for the literal `c(i, s)` of the module being written.
`P` is written as a named constant in each module (and in `main`), or as a literal where the
language has no module-level constants.

All values in the program are non-negative and stay below 2^28. There is no overflow and no
wrapping, so the language's default integer type is fine (64-bit recommended). Because nothing
is negative, `mod` and `div` mean the same in every language: truncating and flooring agree.
`/` below is integer division.

## Module `i`

Each module has exactly these 20 functions, one record type and one sum type, in this order.
Every function is a normal top-level function of its module, written out in full in the source.

```text
record Item { id, size, weight }                # three integer fields

sum type Shape = Circle(r) | Rect(w, h) | Tri(a, b, c) | Empty

base(x):                                        # called by step_1 and by module i+1
  a = x * K[0] + K[1]
  b = a mod P
  return (b * K[2] + K[3]) mod P

step_j(x), for j = 1 .. 13:                     # 13 functions, a chain
  y = base(x) when j == 1, else step_(j-1)(x)
  a = y * K[4j] + x
  b = (a / K[4j + 1] + K[4j + 2]) mod P
  if b mod 2 == 0:
    return (a + b) mod P
  else:
    return (a + b * K[4j + 3]) mod P

make_item(x):
  return Item { id: x mod K[56], size: x mod 1000 + K[57], weight: (x * K[58]) mod P }

item_score(item):
  return (item.id * K[59] + item.size * K[60] + item.weight) mod P

make_shape(x):
  case x mod 4:
    0 -> Circle(x mod K[61] + 1)
    1 -> Rect(x mod K[62] + 1, x mod K[63] + 1)
    2 -> Tri(x mod K[64] + 1, x mod K[65] + 1, x mod K[66] + 1)
    3 -> Empty

area(shape):                                    # a pattern match on the sum type
  case shape:
    Circle(r)    -> 3 * r * r
    Rect(w, h)   -> w * h
    Tri(a, b, c) -> (a * b) / 2 + c
    Empty        -> K[67]

link(x):                                        # the call into the previous module
  i > 0:  return (m<i-1>.base(x) + K[68]) mod P
  i == 0: return (x + K[68]) mod P              # module 0 has no previous module

entry(x):                                       # called by main
  s = step_13(x)
  r = item_score(make_item(s))
  h = area(make_shape(x))
  l = link(x)
  return (s + r + h + l) mod P
```

Rules:

- Write the local bindings (`y`, `a`, `b`, `s`, `r`, `h`, `l`) as local bindings, not as one
  folded expression.
- Write the branch in `step_j` as the language's normal two-way choice: `if`/`else`, `case`, a
  ternary, `cond`. Pick one form and use it in every `step_j`.
- `make_shape` and `area` use the language's sum type and its pattern match, or the closest
  equivalent (see Per-language guidance). `make_shape` may use a `match`/`switch` on `x mod 4`
  or an `if` chain.
- Only `base` and `entry` are used outside their module. Give them the visibility the language
  needs for that (`pub`, exported, capitalised). Keep everything else at the language's normal
  module-private or default visibility.
- Each module imports only module `i - 1` (module 0 imports no other module). It imports
  whatever standard-library item the record or sum type needs (`dataclasses` in Python), and
  nothing else.
- Comments and doc comments are allowed and do not matter. The reference generators put a short
  doc comment on each item.

## main

```text
entries = [m0000.entry, m0001.entry, ..., m<M-1>.entry]    # a literal list, in module order

s = 0
for entry in entries:
  s = (s * 31 + entry(s)) mod P
print s
```

- `entries` is written out in the generated source as a literal list (array, vector, tuple) of
  the `M` function values, in module order. Fold over it with the language's normal loop or
  fold.
- Use the language's normal function-reference form: a method reference in Java and C#,
  `fun m0000:entry/1` in Erlang, `&M0000.entry/1` in Elixir, `m0000/entry` in Clojure.
  Every language in this repository has first-class functions, so none needs `M` sequential
  statements instead.
- `main` must call every module's `entry` exactly once, in order. It imports every module.

## Output

One line: the checksum as a plain decimal integer, then `\n`.

| M   | output   |
| --- | -------- |
| 1   | `470402` |
| 2   | `432917` |
| 3   | `924242` |
| 10  | `522800` |
| 100 | `543623` |
| 200 | `258650` |
| 400 | `783811` |

`M = 2` and `M = 3` are useful for debugging the `link` call and module order.

## Sizes

```toml
gen = "python3 gen.py {args} {out}"
zero = ["1"]
test = ["10"]
bench = ["200"]
```

The value is `M`. Size zero is the smallest valid project: one module and `main`. Unlike the
other benchmarks, every size here is a separate project and every size is measured. At
`M = 200` the Rust project is about 47,000 lines and a clean release build takes about 2 s on
the reference machine (an 8-core Apple Silicon laptop). Time grows about linearly with `M`.

## Measurement

The runner, not the program, does the measuring. For each size it runs `gen.py` once, builds the
project once and checks its output against `expected/<size>.out`, then times:

- **Compiled languages** (AOT, JVM, CLR, BEAM, tsc): the language's `build` command in the
  generated project, from clean, with `clean` as hyperfine's `--prepare`. `clean` follows
  "Build caches and daemons" below, and the build follows "Parallelism". Running the program is
  not timed.
- **Interpreters** (Python, Ruby): one full run, `run` in the generated project. That is the time
  to parse, compile and load every module and run `main`, whose own work is negligible. The run
  is cold: no bytecode cache is read or written, so every timed run does the work that a clean
  build does for the compiled languages. This is a deliberate exception to "default settings" in
  CONVENTIONS.md, because here the compile is the thing measured.
  - Python sets `PYTHONDONTWRITEBYTECODE=1` in `python/impl.toml`. Without it, the untimed check
    run and hyperfine's warm-up write `__pycache__`, and every timed run loads cached bytecode:
    about 0.13 s instead of 0.28 s at `M = 200` on the reference machine. The runner's project
    stamp does not cover the environment, so a project generated before this setting must be
    deleted (`build/python/compile_large/project-*`) so that no old `__pycache__` survives.
  - Cold, about half of Python's time is compiling source to bytecode. Most of the rest is
    creating the classes: each of the 1,000 `@dataclass` decorator calls at `M = 200` generates
    `__init__` and `__eq__` source and runs `exec` on it, on every run. So Python's number is
    mostly class creation and compilation, not loading.
  - Ruby has no bytecode cache by default, so it needs no setting. `Data.define` builds its
    classes in C without generating source.
- **Cheby**, until M3 adds `cheby build`: one full `cheby run` in the generated project. It
  parses, type-checks and JIT-compiles all `20 * M` functions eagerly before `main` runs, then
  runs `main`. The run is reported as the compile time and marked as an estimate. It includes
  process start-up and `main`'s own work: about 12 to 15 ms in all at `M = 1`, and well under
  1 ms of `main` at `M = 200`, against about 250 to 300 ms in all. `cheby check` is timed too
  and reported as front-end time (about 55 to 75 ms at `M = 200`). The runner times the whole
  run and subtracts nothing, so the compile-into-runtime leakage that the size-0 subtraction has
  on the runtime benchmarks does not arise here. What remains is the fixed start-up cost, which
  the per-module slope below cancels.
- Generated sources are counted for lines of code with the language's `extensions`.

### Parallelism

Builds use the parallelism of the language's normal build tool, with its default job count.
Where the normal multi-file build would be one serial compiler call, the project uses the
language's normal parallel driver instead, so that no language is serial only because of how
its build was spelled:

- **C++**: the generator writes a `Makefile` with one object file per module, and `build` is
  `make -j$(sysctl -n hw.ncpu)`. Not one `clang++` call over all files, which is serial.
- **Erlang**: a rebar3 project, `src/m0000.erl`, built with `rebar3 compile`, which compiles
  independent modules in parallel. Not `erlc *.erl` or `erl -make`, which are serial.
- **Nim**: `nim c` with its default `--parallelBuild:0`, which runs one C compiler per core.
- **Odin**: `odin build` with the release flags of `langs/odin.toml`. Its front end is threaded.
  With `-o:speed` its back end is one LLVM unit, and `-use-separate-modules` is not added,
  because it changes the optimised output.
- **Cargo, Go, dune, mix, Gleam, SwiftPM, dotnet, tsc**: their defaults, which are parallel.
- **Cheby**: `cheby run` with its default `-j`, the available parallelism. At `M = 200` on the
  reference machine (8 cores) a run took 0.25 to 0.30 s of wall time and about 1.2 s user plus
  0.1 s system, about 4.5 cores. `cheby run -j 1` took about 0.9 s.
- **Python, Ruby**: serial, by nature.

No flag that changes the optimised output is added only to gain parallelism.

The import chain limits what a parallel driver can do. Module `i` can be compiled only after
module `i - 1`, so a driver that compiles whole modules in dependency order (`go build`, dune in
release, Koka) runs one compiler at a time, whatever its job count. `go build` took 3.20 s with
its default `-p` and 3.21 s with `-p 1`. These rows are serial because of the project's shape,
not because of their build command.

### Build caches and daemons

`clean` removes every output derived from this project's sources, wherever the toolchain keeps
it. Caches of the standard library and of third-party dependencies stay, as in CONVENTIONS.md,
so the time is the time to compile this program. A global, content-addressed cache that would
also hold this project's outputs is moved into `{build}` and reset by `clean`. A shared cache
that would restore this project's outputs is turned off.

No compiler server or daemon survives from one timed build to the next. Every timed build starts
its compiler processes cold, as Rust's and Go's do and as a clean CI build does. A warm server
would be fair only if every language had one, and the compile hyperfine has no warm-up, so
otherwise the first run would pay the server start and the rest would not. The report says
"no compiler servers" for this benchmark.

- **Go**: `GOCACHE={build}/gocache` on `build`. `clean` replaces it with a copy of a seed,
  `{build}/gocache-seed`, made once by building a trivial program that imports what `main.go`
  imports (`fmt`). So the standard library stays compiled, as Rust's does, and every module of
  the project is compiled again. The default `GOCACHE` is global, so deleting the binary alone
  would only relink.
- **Nim**: `--nimcache:{build}/nimcache`. The default is global (`~/.cache/nim/<project>_r`).
  Nim has no separately compiled standard library: every build regenerates the C of every
  module and recompiles only the C files whose text changed. `clean` keeps the std modules' C
  and objects (`@p*`) and removes the project's own (`@m*`), `main.json` and the executable,
  after an untimed warm-up build when the nim version, the flags or the sources changed (the
  std C depends on both). So the standard library stays compiled and every module of the
  project is compiled again.
- **OCaml**: dune with `--cache=disabled`, and `clean` removes the project's `_build`. Dune's
  shared cache would otherwise restore the objects.
- **Zig**: `--cache-dir {build}/zig-cache`, removed by `clean`. The global cache keeps
  `compiler_rt` and libc, which are built once per target, like a dependency.
- **C++**: no `ccache` or `sccache`. `clean` removes the objects and the executable.
- **Swift**: `--scratch-path {build}/swift`. `clean` removes everything in it that comes from the
  project and keeps the SDK caches, `SDKStatCaches.noindex`, `SDKExplicitPrecompiledModules` and
  `ModuleCache.noindex`. They hold only the SDK's stat cache and the `SwiftShims` modules, no
  project code.
- **TypeScript**: no `incremental` or `composite` in `tsconfig.json`, and `clean` removes the
  emitted JavaScript and any `.tsbuildinfo`.
- **Gleam, Elixir, Erlang**: `clean` removes the project's own application directory under
  `build/` or `_build/` and keeps the dependencies.
- **Koka**: `--builddir={build}/koka`, removed by `clean`.
- **C#**: `dotnet build` (or `publish`) with `-p:UseSharedCompilation=false -nodeReuse:false`,
  so neither the VBCSCompiler server nor MSBuild worker nodes outlive the build, and without the
  MSBuild server (`DOTNET_CLI_USE_MSBUILD_SERVER` unset). `clean` removes `obj/` and `bin/`.
- **Scala**: `scala-cli --server=false`, so no Bloop server, and `clean` removes
  `.scala-build`.
- **Java, Clojure**: plain `javac` and plain `clojure` AOT compilation, with no Gradle daemon or
  REPL server. `clean` removes the class directory.
- **Cheby**: no module cache exists before M3, so every run compiles everything.

### Reporting

The report shows, for every language and size:

- the wall time (the median), and next to it the CPU time, user plus system, from the same
  hyperfine runs. `run.py` already records `user` and `system`. Wall time alone hides how many
  cores a build used.
- the per-module slope, `(t(bench) - t(zero)) / (200 - 1)`, in wall time and in CPU time. It
  cancels process start-up and build-tool overhead (cargo's own start-up, Python's interpreter
  start-up, Cheby's 12 to 15 ms), which dominate the comparison at small `M`. Cheby's slope
  keeps the "estimate" label.

Measure on an idle machine. Parallel builds are very noisy on a loaded one: one batch of eight
`cheby run`s at `M = 200` ranged from 0.54 to 0.96 s, and a minute later the same run took
0.25 s.

## Fairness

- Every function is written out in the generated source. No macros, templates, code generation
  at build time, `include!`, `eval`, reflection or metaprogramming to produce the modules.
- No generic or shared helper replaces the per-module functions. Each module has its own `Item`,
  `Shape` and 20 functions.
- No compile-time evaluation tricks: no `const fn`, `constexpr`, `comptime` or annotations that
  force constant folding or inlining. What the optimiser folds on its own is fine.
- No unity build or amalgamation: one file per module, as above. No precompiled headers.
- The build uses the release flags from `langs/<lang>.toml`, unchanged.
- The generated code is in the language's formatter style (`cargo fmt`, `black`, `gofmt`), and
  passes the language's normal linter without warnings (`cargo clippy`). Cheby: `cheby check`
  with no diagnostics. `cheby fmt` is not implemented yet (M5), so the Cheby generator follows
  the style of the examples by hand.

## Per-language guidance

Project shape:

- **Rust**: one crate named `main`, `src/main.rs` with `mod m0000;` lines, `src/m0000.rs`.
  `pub fn base` and `pub fn entry`. Pass `Item` and `Shape` by reference to `item_score` and
  `area`.
- **Cheby**: package `app`, `src/main.cheby`, `src/m0000.cheby`, `import app::m0000`. `base`
  and `entry` have the default (package) visibility, and every other item of a module is `priv`
  (D-162), as the multi-module examples do for their helpers.
- **Python**: `main.py` and `m0000.py` side by side, `import m0000`. `@dataclass` classes for
  `Item` and each `Shape` variant, `type Shape = Circle | Rect | Tri | Empty`, and `match` with
  class patterns. `main.py` imports the modules in order, so no import nests deeply.
- **Go**: one package per module, `m0000/m0000.go`, with exported `Base` and `Entry`, plus
  `go.mod` and `main.go`. All files in one package would clash on `Item` and `base`. `Shape` is
  an interface with four struct types, matched with a type switch.
- **Zig**: `src/m0000.zig`, imported with `@import`. `Shape` is a tagged union, matched with
  `switch`. `/` and `%` on signed runtime integers are compile errors: use `u64`, or
  `@divTrunc` and `@rem`.
- **Odin**: one package per directory, `m0000/m0000.odin`, as for Go. `Shape` is a `union`.
- **C++**: `m0000.hpp` declaring `base` and `entry` in `namespace m0000`, and `m0000.cpp` with
  the definitions, plus a `Makefile` (see Parallelism). One translation unit per module. `Shape` is a `std::variant` of four structs,
  matched with `std::visit` or `std::holds_alternative`/`std::get`.
- **Java**: one class `M0000` per file, with a nested `record Item` and a nested
  `sealed interface Shape` with four `record` variants, matched with a `switch` pattern.
  `main` holds an array or `List` of `IntUnaryOperator`/`LongUnaryOperator` method references.
- **C#**: one `static class M0000` per file, nested `record Item` and an abstract `record Shape`
  with four derived records, matched with a `switch` expression. One project.
- **Scala**: one `object M0000` per file, `case class Item`, `enum Shape`.
- **Clojure**: one namespace per file, `defrecord Item` or a map
  with keyword keys, and `Shape` as a map or vector tagged with a keyword (`[:circle r]`),
  matched with `case` on the tag. Build means AOT compilation of all namespaces.
- **TypeScript**: one `.ts` file per module with ES module imports. `Item` is an interface or
  type, `Shape` a discriminated union on a `kind` field, matched with `switch`. `/` is float
  division: write `Math.trunc(a / k)`. Every value stays below 2^28, so `number` is exact.
- **Swift**: one file per module. Wrap each module's items in a caseless `enum M0000` used as a
  namespace, with a nested `struct Item`, a nested `enum Shape` with associated values, and
  `static func`s. One Swift module for the whole project.
- **Erlang**: a rebar3 project with `src/m0000.erl` per module (see Parallelism),
  `-record(item, {id, size, weight})` or a map, `Shape` as tagged tuples (`{circle, R}`,
  `empty`), matched in function clauses or `case`. Export `base/1` and `entry/1`. `link/1`
  clashes with the auto-imported BIF `erlang:link/1`, and `erlc` warns about the call, so add
  `-compile({no_auto_import, [link/1]}).` to each module. Elixir needs nothing, because
  `Kernel` has no `link/1`.
- **Elixir**: `lib/m0000.ex` per module (`defmodule M0000`), `defstruct` for `Item`, tagged
  tuples for `Shape`. `defp` for private functions.
- **Gleam**: `src/m0000.gleam` per module, a record type and a custom type. `pub fn base` and
  `pub fn entry`.
- **OCaml**: `m0000.ml` per module (dune), a record type and a variant type. A `.mli` is not
  needed. Avoid the keyword `rec` as a name.
- **Koka**: `m0000.kk` per module, `struct item` and a `type shape`.
- **Nim**: `m0000.nim` per module, an `object` for `Item` and an object variant (or a `case`
  object) for `Shape`. Export with `*`. `/` on integers returns a float: use `div` and `mod`.
- **Ruby**: `m0000.rb` per module (`module M0000`), `Data.define` or `Struct` for `Item` and the
  variants, matched with `case`/`in`. `main.rb` uses `require_relative`. Ruby keeps no bytecode
  cache, so every run parses everything (see Measurement).

## Reference

`cheby/gen.py`, `python/gen.py` and `rust/gen.py` are the reference generators. They agree on
every size above.
