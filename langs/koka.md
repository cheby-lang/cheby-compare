# Koka in cheby-compare

Koka 3.2.9 from Homebrew (`/opt/homebrew/bin/koka`, a plain symlink to the real binary). Koka
compiles to C and calls clang. Memory is managed by Perceus reference counting, as in Cheby, with
in-place reuse of unshared values (FBIP). `setup/koka.sh` checks the toolchain and does one smoke
build. Nothing is downloaded.

## Project layout

Each implementation is one file plus optional modules, in `benchmarks/<bench>/koka/`:

```text
benchmarks/<bench>/koka/
  main.kk      module main, with `pub fun main()`. Start it with a `//` comment saying what it does.
  other.kk     optional modules, imported as `import other`. Koka's search path includes the cwd.
  impl.toml    optional: libs, notes, or overrides of langs/koka.toml keys
```

Do not give a module a name that starts with `std` (file `std*.kk`). `clean` keeps every file
named `std_*` in the build dir, because those belong to the standard library.

## Build, clean, run (langs/koka.toml)

- `build`: `koka -O2 -v0 --builddir={build}/koka -o {build}/main main.kk`. `-O2` is Koka's
  optimised build. Its C side is `clang -O2 -g -DNDEBUG -march=armv8.1-a+crypto+aes -mtune=native`.
  The `-march`/`-mtune` are Koka's own defaults, not something we add. It is one cold `koka`
  process, with no server.
- `env`: the Xcode toolchain's `bin` goes first on `PATH`, so koka uses the real Apple clang and
  not the `/usr/bin/clang` xcrun trampoline. `SDKROOT` points at the macOS SDK, as in
  `langs/cpp.toml`.
- **Extra flags** go in `impl.toml` through koka's own environment variable. `build` cannot hold
  shell syntax, because hyperfine runs it without a shell. Koka puts `koka_options` in front of
  its arguments, in `build` and in `clean`'s warm-up builds alike:

  ```toml
  env = { koka_options = "--ccopts=-ffp-contract=off" }   # mandelbrot (SPEC: no FMA)
  ```

  `env` merges key by key with the language's env, so PATH and SDKROOT stay.
- `clean`: koka copies the standard library (`std_*.kki/.c/.h/.o`), its runtime (`kklib.o`) and
  `libuv.a`/`libpcre2-8.a` into `{build}/koka/v3.2.9/clang-drelease-<hash>/`, and compiles kklib
  and std there. `clean` keeps those files and deletes everything else: your modules
  (`main.*`, `main__main.*`, `other.*`) and the executables. It then runs one untimed warm-up build,
  or two when std objects are stale, and prunes again. Two cases make std objects stale: a fresh
  build dir, and a program that has just started importing another std module. In both, koka copies
  the precompiled std objects first and recompiles them on the next build. So the timed build
  always compiles and links only your program. A clean takes about 0.5 s, or about 3 s after a new
  std import.
- `run`: `{build}/main {args}`. `artifact`: `{build}/main`.

Measured on hello_world, with the machine busy: clean then build ≈ 440 ms (5 runs, ±4 ms). Std
objects stay untouched and `main.o` is rebuilt. Start-up is ≈ 1.7 ms, and the binary is 1.0 MB.
Koka recompiles the main module on every build even without `clean`, so an incremental build is
about as slow. A build with more std imports (`std/os/file`, `std/num/float64`) takes about
0.8 s, all of it interface loading and linking.

By hand, from the repository root:

```sh
python3 runner/run.py verify -l koka -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py build -l koka -b <bench>        # build log: build/koka/<bench>/build.log

# or manually, in benchmarks/<bench>/koka (same env as the toml):
export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
B=../../../build/koka/<bench>
koka -O2 -v0 --builddir=$B/koka -o $B/main main.kk && $B/main 10
```

`-v0` still prints two `vfs: [...]` lines on stderr. That is harmless noise from koka 3.2.9. Use
`-v1` to see which modules get loaded, compiled and linked.

## Third-party dependencies

Koka has no package manager, and the conventions allow no library for Koka. JSON is a
hand-written recursive-descent parser and serializer in the program (json_roundtrip SPEC). If code
must be shared, put it in another `.kk` module in the same implementation directory. Never import
it from another benchmark's directory. Name nothing in `libs`. Use `notes` to say "hand-written
parser" and similar.

## Standard library (3.2.9) and gotchas

- **No collections.** `std/data/{map,dict,imap,iset,set,array}` are 13–15-line stubs ("Todo").
  There is no hash map, no ordered map, no sort and no mutable array. Write what the SPEC asks for:
  a red-black tree (see `samples/basic/rbtree*.kk` under
  `/opt/homebrew/Cellar/koka/3.2.9/share/koka/v3.2.9/lib/samples`), a merge sort, and so on, and
  name them in `notes`. `vector<a>` is an immutable-by-default array with O(1) `v[i]` (raises
  `exn`). Inside a function, `var v := vector(n, 0)` plus `v[i] := x` updates it in place when the
  vector is unshared. `vector-init(n, f)`, `.list` and `list.vector` also exist.
- **Integers.** `int` is arbitrary precision, with a fast path for small values. It never overflows,
  so it is right for counters and checksums, but it never wraps. For 64-bit LCG, xorshift or FNV
  arithmetic, `import std/num/int64` and use `int64`. Its `+`, `-` and `*` wrap (two's complement).
  It has `and`, `or`, `xor`, `shl(i, n)`, `shr(i, n)` (logical) and `sar(i, n)` (arithmetic); the
  shift amount is a plain `int`. Convert with `x.int64` and `i.int`. Use `i.uint` to read an
  `int64` as unsigned 64-bit, and `x.uint64` for an `int` in 0..2^64-1. Write literals as
  `0x7FFF_FFFF_FFFF_FFFF.int64`. `-16.int64` parses as `-(16.int64)`. Watch overload ambiguity:
  `sar(x, 2.int64)` fails to resolve, so pass `sar(x, 2)`. `int32` lives in `std/num/int32`.
- **Rounding.** `round` on `float64` rounds **half to even** (`2.5.round == 2.0`, and `.int`
  rounds the same way). CONVENTIONS want half away from zero, so write it yourself, e.g.
  `fun round-away(x : float64) : int { val t = x.truncate; (if abs(x - t) >= 0.5 then t + (if x < 0.0 then -1.0 else 1.0) else t).int }`.
  Never print floats with `show`: print `round-away(x * 1.0e9).show`.
- **Effects.** Any function that may not terminate (general recursion) needs `div` in its effect,
  e.g. `fun loop(i : int) : <console,div> ()`. Top-level functions can usually omit their type,
  or give it fully. `main` can have its effect inferred.
- **Recursion depth.** The default 8 MB stack overflows (SIGSEGV, exit 139) on plain non-tail
  recursion somewhere between 100k and 1M frames. Tail calls are compiled to loops. Std list
  functions (`map`, `foldl`, `++` and others) are tail-recursive or use TRMC, so they are safe on
  long lists. Your own `Cons(f(x), go(xs))` is TRMC too. Write deep loops as tail recursion, or
  with `for`/`while` over a local `var`. (`fold`, `foreach`, `for(lo, hi)`, `repeat`, `while`
  exist; `for` includes `hi`.)
- **Arguments.** `import std/os/env`, then
  `get-args().head.default("0").parse-int.default(0)` (`parse-int : string -> maybe<int>`).
  Size 0 must take the same path.
- **Files.** `import std/os/file` and `import std/os/path`, then `read-text-file(path(name))`
  (effect `<fsys,exn>`). `split(s, "\n")` and `split(s, " ")` give `list<string>`. Strings are UTF-8,
  and `cmp`/`<` on strings compare bytes.
- **Output.** `println(s)` writes to a buffered stdout: 1M lines take ≈ 50 ms, so no extra buffering
  is needed. `show` on `int`/`int64` prints plain decimal. Build long lines with `++` or
  `join(list, sep)`.
- **Concurrency.** `std/async` ships with the installed Koka (precompiled, linked with libuv). It
  has `async { ... }`, `interleaved(a, b)` / `interleaved(list)` (strands, cooperatively scheduled
  on one thread) and `channel()` / `emit` / `receive`, plus `promise()` / `await` / `resolve`. A
  quick ping-pong over two channels with 10,000 round trips compiled and ran (0.2 s; the channel
  keeps its waiters in a list that `++` appends to). Follow each SPEC's Koka row. ping_pong says
  to use `std/async`. spawn_many says to write a cooperative scheduler with an effect handler.
  prime_sieve says n/a ("no tasks or channels"), which contradicts ping_pong.
- **Floats.** `std/num/float64` has `sqrt`, `abs`, `truncate`, `floor`, and the literal `1.0e9`.
  clang fuses `a*b+c` into FMA at -O2 by default. Where a SPEC forbids FMA (mandelbrot), set
  `koka_options = "--ccopts=-ffp-contract=off"` as shown above.
- Don't add `--no-debug`, `-O3`, `--ccopts=-march=...`, `--stack` or `--heap` to the release flags.
