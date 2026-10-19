# Nim in cheby-compare

Nim 2.2.12 from Homebrew (`/opt/homebrew/bin/nim`, a symlink into the Cellar, not a shim). It
compiles to C and builds with Apple clang 21 (`-O3` under `-d:release`). The standard library
covers every benchmark: `std/json`, `std/tables`, `std/algorithm`, `std/strutils`,
`std/typedthreads` and the system `Channel[T]`. **No third-party packages** are needed or allowed
(CONVENTIONS "Standard library first": Nim has JSON in std).

## Project layout

One program per implementation, in `benchmarks/<bench>/nim/`:

```text
benchmarks/<bench>/nim/
  main.nim     the program; more modules may sit next to it and be imported (`import foo`)
  impl.toml    optional: libs, notes, or overrides of langs/nim.toml keys
```

No `.nimble` file: a single `main.nim` is Nim's smallest normal project. Start `main.nim` with a
`#` comment saying what the program does (comment prefix is `#`; LOC counts `.nim` files).
Two-space indentation, as `nimpretty` writes it.

## Build, clean, run (langs/nim.toml)

- `build`: `nim c -d:release --skipUserCfg --hints:off $nim_flags --nimcache:{build}/nimcache --out:{build}/main main.nim`.
  `-d:release` is Nim's release build. ORC (`--mm:orc`) and `--threads:on` are 2.2 defaults and
  are not repeated. No `-d:danger`, no `--passC:-flto`, no `-march=native`. `--skipUserCfg`
  ignores a `~/.config/nim/nim.cfg`. A `main.nim.cfg`, `nim.cfg` or `config.nims` in the
  implementation directory would still be read, so do not add one with extra flags; put flags
  in `impl.toml` where the reviewer sees them (below). `nim_flags` is empty by default; the
  config sets it, so a `nim_flags` in the caller's environment never reaches the build.
- `clean` keeps the compiled standard library (CONVENTIONS, `langs/<lang>.toml`). The nimcache
  holds one generated C file and one object per module: `@m*` for the program's own modules
  (`main.nim` and its siblings), `@p*` for `system` and the std modules. `clean` removes the
  `@m*` files, `main.json` and the executable, and keeps the `@p*` files.
- Nim has no separately compiled standard library: every build runs the whole front end and
  regenerates the C of every module, std included. It rewrites, and so recompiles, only the C
  files whose text changed. The C of a std module depends on the program (dead-code
  elimination) and on the flags (each file's header holds the C compiler command). So the kept
  objects are reused only when they were built for this program with these flags.
- `clean` makes sure they were. It does an untimed warm-up build, then prunes again, when the
  nimcache has no `@psystem.nim.c.o` or when `{build}/.nim-warm` does not match the current
  nim version, `nim_flags` and the text of `./*.nim`. A changed program, such as a new std
  import, therefore gets a new warm-up. Otherwise `clean` only prunes (≈ 20 ms). The warm-up
  command in `clean` must stay the same as `build`. There is no compiler daemon. The global
  `~/.cache/nim` is never used.
- `run`: `{build}/main {args}`, the executable. `artifact`: `{build}/main`.

So a timed build is the Nim front end over the program and every std module it imports, the C
generation, clang on the program's own modules only, and the link. Measured on hello_world
(hyperfine, `clean` as `--prepare`): ≈ 220 ms, against ≈ 375 ms when `clean` removed the whole
nimcache. The same build without `--hints:off` prints one `CC:` line per module
clang compiles; after `clean` it should list only the program's modules. If it lists
`system.nim` or `std/...`, the warm-up did not use the same flags as `build`. Start-up
≈ 1.5-2 ms, executable 75 KB, linked only against libSystem.

By hand, from the repository root:

```sh
python3 runner/run.py verify -l nim -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py build -l nim -b <bench>

# or manually, in benchmarks/<bench>/nim:
B=../../../build/nim/<bench>
nim c -d:release --skipUserCfg --hints:off --nimcache:$B/nimcache --out:$B/main main.nim
$B/main 10
```

### Extra flags in impl.toml

Put them in `nim_flags`, never in an override of `build`. `build` and the warm-up in `clean`
both expand `nim_flags`, so the kept std objects are built with the same flags. An override of
`build` alone would warm the cache with the default flags, and every timed build would compile
the standard library again. Mandelbrot needs contraction off (its SPEC):

```toml
env = { nim_flags = "--passC:-ffp-contract=off" }
notes = "-ffp-contract=off, as the SPEC requires for languages compiled through C"
```

Only mandelbrot needs it. nbody allows the default contraction (clang's `-ffp-contract=on`), and
spectral_norm's output does not depend on it.

## Adding a third-party package (not expected for Nim)

Should one ever be needed: add `name@version` to `NIMBLE_PKGS` in `setup/nim.sh` and run it. It
installs with `nimble install -y --nimbleDir:build/nimble`, never into `~/.nimble`. Then the
implementation's `impl.toml` adds `--NimblePath:{root}/build/nimble/pkgs2` to its `build` and names
the package in `libs = ["name version"]`. `clean` never touches `build/nimble`. Nim compiles a package's
sources into the program's nimcache like std, so check which prefix its files get there: `clean`
keeps `@p*` and removes `@m*`, and a package module must be kept like std.

## Gotchas

- **Integers.** `int` is 64-bit here, the same as `int64`. **Overflow checks stay on under
  `-d:release`** (only `-d:danger` removes them): signed overflow raises `OverflowDefect` and
  kills the program. Write LCG, xorshift and FNV generators on `uint64` (or `uint32`), which wrap
  silently: `x = x * 6364136223846793005'u64 + 1442695040888963407'u64`. Literal suffixes:
  `'u64`, `'u32`, `'i64`. `uint64(x)` on a negative `int` is not checked
  and reinterprets the bits (`uint64(-1) == 2^64 - 1`), as `cast[uint64](x)` does. The way back
  is different: `int(u)` is range-checked and raises above `high(int)`, so use `cast[int](u)` to
  reinterpret.
- **Bounds and `assert` checks** stay on in release too. That is Nim's release default; keep it.
- **`div` and `mod`** truncate toward zero: `-7 div 2 == -3`, `-7 mod 2 == -1`. `floorMod` from
  `std/math` gives the floored remainder. `/` on ints returns a `float`. `shr` on a signed int
  is arithmetic (`-8 shr 1 == -4`). On unsigned it is logical.
- **Float output.** Print floats as integers per the spec:
  `int64(round(x * 1e9))` with `round` from `std/math`, which rounds half away from zero
  (`round(-2.5) == -3.0`). `$` and `echo` on a float give shortest-round-trip text; never print
  that.
- **Output.** `echo` writes its arguments, then `\n`, **and flushes stdout on every call**. That
  is fine for a few lines. For many lines, build a `string` and `stdout.write` it once, or call
  `stdout.write`/`stdout.writeLine`, which buffer, and `flushFile(stdout)` is done at exit.
  `quit(0)` also flushes the C stdio buffers.
- **Arguments.** `import std/os`, then `paramStr(1)` and `parseInt` from `std/strutils`.
  `commandLineParams()` returns a `seq[string]`.
- **Recursion.** No recursion limit beyond the C stack: 8 MB on the main thread (macOS default)
  and about 2 MB (`256 * 1024 * sizeof(int) - 4096`) on a `createThread` thread. Deep recursion
  inside a worker thread overflows sooner.
- **ORC and trees.** `ref object` types are reference-counted, and ORC also runs a cycle
  collector for types that could be cyclic. binary_trees' SPEC requires
  `type Node {.acyclic.} = ref object`.
- **Threads.** `import std/typedthreads` for `Thread[T]`, `createThread`, `joinThread`. A thread
  proc needs `{.thread.}` and must not touch GC'd globals. A running `Thread[T]` must not move:
  preallocate with `newSeq[Thread[T]](n)`, never `add` to a growing seq. `Channel[T]` (system,
  no import) has to live in shared memory when several threads use it: allocate with
  `cast[ptr Channel[int]](allocShared0(sizeof(Channel[int])))`, then `open(ch[], maxItems = 1)`,
  `send`, `recv`. System channels cannot be closed, so end with `quit(0)` where the SPEC allows.
  Sending a `ref` or `string` through a channel deep-copies it.
- **JSON.** `std/json`: `parseJson`, `JsonNode` with `kind` (`JObject`, `JArray`, `JInt`,
  `JFloat`, `JString`, `JBool`, `JNull`), `getInt`, `getFloat`, `getStr`, `elems`, `fields`
  (an `OrderedTable`, so key order is kept), `%`/`%*` to build, `$` for compact output and
  `pretty` for indented. Check the exact formatting the SPEC wants against `$`.
- **Tables.** `std/tables`: `Table[K, V]`, `CountTable[K]` (`inc`, `sort`), `OrderedTable`.
  `t[k]` raises `KeyError` when absent; use `getOrDefault`, `mgetOrPut` or `hasKey`.
- **Warnings** such as `UnusedImport` print during the build. Leave none in finished code.
