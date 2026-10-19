# C++ (`cpp`) guide for benchmark authors

Toolchain: Apple clang 21 (`clang-2100.3.34.2`), libc++, arm64 macOS. Config: `langs/cpp.toml`.
Extra setup: `setup/cpp.sh` (idempotent; checks for Xcode.app's clang++, make and SDK, and installs
`nlohmann-json` 3.12.0 from Homebrew). The Command Line Tools alone are not enough.

## Layout

Every implementation is a single file:

```text
benchmarks/<bench>/cpp/
  main.cpp      the whole program
  impl.toml     optional: libs, notes, or a `build` override
```

The default `build` compiles exactly `main.cpp` (no glob), so keep everything in that one file.
No Makefile or CMake is needed, except for `compile_large` (below).

## What the config does

```text
build    = <clang++> -std=c++23 -O3 -o {build}/main main.cpp
clean    = rm -f {build}/main
run      = {build}/main {args}
artifact = {build}/main
env      = SDKROOT=<MacOSX.sdk>, CXX=<clang++>, CXXFLAGS="-std=c++23 -O3"
```

- `-O3` is CMake's Release default, which CONVENTIONS "Optimised builds" names for C++. No
  `-march=native`, no LTO, no `-ffast-math`.

- `<clang++>` is `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++`,
  the real compiler. `/usr/bin/clang++` (and `/usr/bin/make`) are xcrun trampolines that add
  about 6 ms per start, which the "no shims or proxies" rule forbids. Called directly, clang needs
  `SDKROOT`, which the config's `env` sets. Without it you get `'iostream' file not found`.
- One cold compiler process compiles and links. No ccache, no PCH, no daemon. `clean` deletes the
  executable, so every timed build compiles the whole program again. hello_world: about 0.30 s per
  clean build; compile of one TU including `<nlohmann/json.hpp>`: about 1.5 s.
- **No shell syntax in `build`.** The runner's compile timing passes `build` to hyperfine 2.0,
  which runs the command **without a shell** by default. `$VAR`, globs (`*.cpp`), `&&`, `$(...)`
  would break `measure` even though `verify` works (verify uses `sh -c`). `clean` is fine: it runs
  as hyperfine's `--prepare`, which always uses a shell. The runner creates `{build}` itself.

## Building and running by hand

From `benchmarks/<bench>/cpp/`:

```sh
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
CXX=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++
mkdir -p /tmp/cppb && $CXX -std=c++23 -O3 -o /tmp/cppb/main main.cpp && /tmp/cppb/main 10
```

Or through the runner, which is what counts:

```sh
python3 runner/run.py verify -l cpp -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py measure -l cpp -b <bench> --quick --out /some/scratch.json  # optional smoke test of the timed path
```

The build log is in `build/cpp/<bench>/build.log`.

## Per-benchmark flags (impl.toml)

An `impl.toml` key replaces the `langs/cpp.toml` key (only `env` is merged per variable), so an
extra flag means overriding the whole `build` line. Keep the compiler path and the release flags
identical and only append:

- **mandelbrot** (SPEC requires no FMA contraction):

  ```toml
  build = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -std=c++23 -O3 -ffp-contract=off -o {build}/main main.cpp"
  notes = "-ffp-contract=off, as the SPEC requires"
  ```

- **nbody, spectral_norm**: the SPECs allow clang's default contraction (`-ffp-contract=on`).
  Use the default build. Never write `fma()` by hand. In spectral_norm the default costs about
  25-35%: clang fuses `sum += entry * x[j]` into an fmadd on the loop-carried chain, which has a
  longer latency than fadd. Its impl.toml notes this; the flag stays at the default.

## Third-party dependency: nlohmann/json (json_roundtrip)

It is header-only, installed by `setup/cpp.sh` to `/opt/homebrew/opt/nlohmann-json/include`.
Add the include path with `-isystem` and name the library:

```toml
build = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -std=c++23 -O3 -isystem /opt/homebrew/opt/nlohmann-json/include -o {build}/main main.cpp"
libs = ["nlohmann/json 3.12.0"]
```

```cpp
#include <nlohmann/json.hpp>
using json = nlohmann::ordered_json;   // SPEC: ordered_json, not json (std::map sorts keys)
```

Being header-only, it is recompiled on every clean build; that is its normal cost, not a cache
to keep. No other third-party library is allowed (CONVENTIONS "Standard library first").

## compile_large

The SPEC wants a generated `Makefile` with one object per module, built with parallel `make`.
Notes for its author:

- Use the real make, `/Applications/Xcode.app/Contents/Developer/usr/bin/make` (GNU Make 3.81),
  not the `/usr/bin/make` trampoline.
- `env` already exports `CXX` (the real clang++) and `CXXFLAGS="-std=c++23 -O3"`, so make's
  implicit `%.o: %.cpp` rule and `$(CXX) $(CXXFLAGS)` in the Makefile pick them up. Keep `SDKROOT`.
- `make -j$(sysctl -n hw.ncpu)` is shell syntax, which hyperfine 2.0 does not run without a shell
  (see above), so `build` wraps it: `sh -c 'exec <make> -j"$(/usr/sbin/sysctl -n hw.ncpu)"
  OUT={build}'`. That costs about 2 ms of sh start-up and keeps the job count right on any
  machine. Output dir: objects and `main` under `{build}` (the runner gives each size its own
  `{build}`, `build/cpp/compile_large/out-<size>`), and `clean` = `rm -rf {build}/*.o {build}/main`.
- `Shape` is matched with `std::visit` and a plain per-module visitor struct with four
  `operator()` overloads, not the variadic `overloaded` template (Fairness: no templates).

## Gotchas

- **Printing**: use `<iostream>` and `std::cout`, not `<print>`/`std::println` (hello_world SPEC:
  `<print>` is 2.3x the compile time and 3.4x the binary). `'\n'`, not `std::endl` (which flushes
  every line). For many output lines, `std::ios::sync_with_stdio(false)` is the usual idiom; keep
  it out of hello_world (SPEC forbids buffering set-up there).
- **Integer widths**: use `std::int64_t` / `std::uint64_t` from `<cstdint>`. `long` is 64-bit on
  this target, but say what you mean. Signed overflow is undefined behaviour: do LCG/xorshift
  arithmetic in `std::uint64_t` (wraps mod 2^64) and convert at the end. `>>` on a negative signed
  value is arithmetic in C++20 and later.
- **Parsing arguments**: `std::stoll(argv[1])` or `std::from_chars` (`<charconv>`); both fine.
- **Float output**: the SPECs print floats as integers, `round(x * 10^k)` half away from zero,
  which is exactly `std::llround` / `std::round` (`<cmath>`).
- **Concurrency**: `std::thread`, `std::jthread`, `std::async(std::launch::async, ...)`,
  `std::mutex`, `std::condition_variable` all work with plain `-std=c++23` (no `-pthread` needed
  on macOS). Apple libc++ `std::async(launch::async)` starts one OS thread per call but detaches
  it, so `future.get()` does not wait for the thread to exit. Where a SPEC counts joining a thread
  (spawn_many), use `std::jthread` or `std::thread` + `join()`, which do. Limits: 4096 threads per process (`kern.num_taskthreads`); secondary threads get a 512 KiB
  stack by default, the main thread 8 MiB. Do not change stack sizes unless the SPEC allows it.
- **Recursion**: deep recursion on a secondary thread hits the 512 KiB stack long before the main
  thread's 8 MiB. Binary-tree depths in the SPECs are far below either.
- **Hash maps**: `std::unordered_map<std::string, std::int64_t>`; for `std::string_view` keys
  into a buffer, make sure the buffer outlives the map.
- **Optimisation level**: `-O3`, CMake's Release default (CONVENTIONS "Optimised builds"). Every
  `build` override keeps it. No `-march=native`, no `-flto`, no `-ffast-math`.
