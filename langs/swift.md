# Swift (`swift`) guide for benchmark authors

Toolchain: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`) from Xcode's default toolchain, arm64 macOS.
Config: `langs/swift.toml`. Extra setup: `setup/swift.sh` (idempotent; installs nothing, warms the
shared module cache). No third-party library is needed or allowed: Foundation ships with the SDK
and has `JSONDecoder`/`JSONEncoder` (CONVENTIONS "Standard library first").

## Layout

Every implementation is a single file, compiled as one module named `main`:

```text
benchmarks/<bench>/swift/
  main.swift    the whole program; its top-level code is the entry point
  impl.toml     optional: notes, or a `build` override
```

Start `main.swift` with a `//` comment that says what the program does. Top-level code, including
top-level `await`, is the normal entry point of a `main.swift`; do not add an `@main` type as
well (the two conflict). No `Package.swift` is needed, except for `compile_large` (below).

## What the config does

```text
build    = <swiftc> -O -wmo -swift-version 6 -module-cache-path {root}/build/swift/module-cache -o {build}/main main.swift
clean    = rm -f {build}/main
run      = {build}/main {args}
artifact = {build}/main
env      = SDKROOT=<MacOSX.sdk>, PATH=<toolchain>/usr/bin:$PATH
```

- `<swiftc>` is `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc`.
  `/usr/bin/swiftc` and `/usr/bin/swift` are xcrun trampolines, forbidden by "no shims or
  proxies". Called directly, swiftc needs `SDKROOT` (set in `env`); without it `import Foundation`
  fails.
- Release flags: `-O` plus whole-module optimisation, which is what SwiftPM's release build uses.
  No `-Ounchecked`, no `-lto`, no `-target-cpu`, no `-enforce-exclusivity=unchecked`.
- **Language mode 6** (`-swift-version 6`), the mode of a package made by Swift 6.4's
  `swift package init` (tools-version 6.4). Bare `swiftc` would default to mode 5. Strict
  concurrency checking is on, see Gotchas.
- **Cold compile.** swiftc has no daemon or build server: one driver, one `swift-frontend`, one
  link, and only `{build}/main` is written (objects go to `$TMPDIR` and are deleted). The SDK and
  standard-library modules (Swift, Foundation, Dispatch, Synchronization, ...) are compiled from
  their `.swiftinterface` files into the shared module cache `build/swift/module-cache` on first
  use. That cache is the standard library's compiled artifacts: `setup/swift.sh` warms it and
  `clean` keeps it, so the timed build compiles and links only the program.
  - hello_world: about 165 ms per clean build, 1.2 ms start-up, 50 KB executable.
  - A small program that imports Foundation: about 0.33 s per clean build. With an empty module
    cache the first build takes about 1.7 s, which is the cache being filled, not the program.
- **No shell syntax in `build`** (`$VAR`, globs, `&&`): the runner's compile timing runs `build`
  through hyperfine without a shell. `verify` uses `sh -c` and would hide the problem. `clean` is
  fine (it runs as hyperfine's `--prepare`).

## Building and running by hand

From `benchmarks/<bench>/swift/`:

```sh
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
mkdir -p /tmp/swb && $SWIFTC -O -wmo -swift-version 6 \
  -module-cache-path ../../../build/swift/module-cache -o /tmp/swb/main main.swift && /tmp/swb/main 10
```

Or through the runner, which is what counts:

```sh
python3 runner/run.py verify -l swift -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py measure -l swift -b <bench> --quick --out /some/scratch.json  # smoke test of the timed path
```

The build log is in `build/swift/<bench>/build.log`. If `build/swift/module-cache` was deleted,
run `./setup/swift.sh` again (or just build once; the first build refills it).

## Overrides (impl.toml)

An `impl.toml` key replaces the `langs/swift.toml` key (only `env` is merged per variable), so a
change to the build means repeating the whole line. Keep the compiler path, the flags and the
module cache identical, and only change what you must, e.g. more source files listed explicitly:

```toml
build = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -O -wmo -swift-version 6 -module-cache-path {root}/build/swift/module-cache -o {build}/main main.swift Channel.swift"
notes = "..."
```

Prefer a single `main.swift`; no benchmark needs more.

## Third-party dependencies

None. Foundation is part of the platform SDK, so JSON uses `JSONDecoder`/`JSONEncoder` and needs
no `libs` entry. If a dependency were ever unavoidable it would mean SwiftPM (a `Package.swift`,
`swift-build -c release --scratch-path {build}/swift`, deps resolved once by `setup/swift.sh`
with `swift package resolve`), which costs about 2 s of extra build overhead even for hello world
and a different `clean`; ask before going there.

## compile_large (SwiftPM)

The SPEC asks for SwiftPM with `--scratch-path {build}/swift`, removed by `clean`. Notes from a
trial with Swift 6.4:

- Call the real tool, `swift-build` from the toolchain (on `PATH` first through `env`), not
  `/usr/bin/swift build`: `swift-build -c release --scratch-path {build}/swift`.
- SwiftPM 6.4 builds with the Swift Build engine: the scratch path holds `out/` with
  `Intermediates.noindex`, `ModuleCache.noindex`, `SDKExplicitPrecompiledModules` and the
  products (`{build}/swift/release/main` is a symlink into `out/Products/Release`). So deleting
  the scratch path also drops the SDK modules it precompiled; that is what the SPEC prescribes.
- Release builds emit a `.dSYM` (SwiftPM passes `-g` in release by default).
- An empty hello-world package: about 2.3 s per build after deleting the scratch path. No
  process stayed running after the build.
- `swift package init --type executable` in 6.4 also adds
  `.enableUpcomingFeature("ApproachableConcurrency")`; it is irrelevant to compile_large, and
  the single-file benchmarks do not use it (see Gotchas, concurrency).

## Gotchas

- **Integer widths and overflow.** `Int` is 64-bit. Arithmetic overflow **traps** in `-O` builds
  (it is not UB and not wrapping). For LCG/xorshift generators use `UInt64` and the wrapping
  operators `&+`, `&-`, `&*`. Shifts never trap: `<<`/`>>` are "smart" shifts (an over-shift
  gives 0), `&<<`/`&>>` mask the amount like C; either is fine for constant amounts. Convert with `Int(truncatingIfNeeded:)` or
  `Int(x)` when the value fits. `%` on negative `Int` keeps the dividend's sign, like C.
- **Float output.** `round(x * 10^k)` half away from zero is `(x * 1e6).rounded()` (default rule
  `.toNearestOrAwayFromZero`), then `Int(...)`. `2.5.rounded() == 3`, `(-2.5).rounded() == -3`.
  Never print a `Double` directly. Do not use `.addingProduct` (that is an FMA); Swift does not
  contract `a*b + c` on its own.
- **Arguments.** `CommandLine.arguments[1]`, `Int(...)!`. hello_world must not touch them.
- **Dictionary/Set iteration order is random per process** (seeded SipHash). Sort before
  printing anything that came out of a `Dictionary` or `Set`.
- **JSON key order: `JSONEncoder` does not keep it.** Verified in 6.4: it writes keys in a
  different order on every run (it goes through a hash map), with synthesized `Codable` and with
  a hand-written `encode(to:)` alike. `.sortedKeys` gives alphabetical order, which is not the
  SPEC's order. So `json_roundtrip` needs `JSONDecoder` for parsing plus a small hand-written
  serializer for the output, as its SPEC allows; say so in `impl.toml` `notes`.
  `JSONSerialization` returns `NSDictionary`, also unordered. `JSONEncoder` also escapes `/` as
  `\/` unless `.withoutEscapingSlashes` is set.
- **Strings are slow if used naively.** `String` indexes by grapheme cluster. For tokenizing or
  byte-level work (word_freq, a JSON checksum) use `string.utf8` / `Array(data)` as `[UInt8]`
  and compare bytes; build `String(decoding: bytes[a..<b], as: UTF8.self)` only for map keys.
  Read a file with `try String(contentsOfFile: path, encoding: .utf8)` or
  `FileManager.default.contents(atPath:)` (`import Foundation`).
- **Printing many lines.** Each `print` takes the stdout lock and is fairly slow; for more than a
  few hundred lines build one `String` (or `[String]` joined with `"\n"`) and print it once.
  `print` adds the `\n` itself. hello_world uses one plain `print("Hello, world!")`.
- **Swift 6 language mode in top-level code.** Top-level variables in `main.swift` are
  `@MainActor`-isolated. A top-level `let` of a Sendable type (e.g. `let n = Int(...)!`) can be
  read from any function, but a top-level `var` mutated from a plain `func` is a compile error
  ("main actor-isolated var ... can not be mutated from a nonisolated context"). Keep mutable
  state inside functions or pass it as parameters / `inout`; do not reach for
  `nonisolated(unsafe)`. Classes captured by tasks must be `Sendable` (`final class` with `let`
  fields, or an `actor`).
- **Concurrency.** `Task { }`, `Task.detached { }`, `withTaskGroup(of:)` + `group.addTask`,
  `AsyncStream.makeStream(of:)`, actors and `Mutex` (`import Synchronization`) all work with the
  default deployment target (macOS 27) and need no flags. Tasks run on the cooperative pool (one
  thread per core); the runtime's default thread count must not be changed. Top-level `await`
  works in `main.swift` (verified: `await withTaskGroup ...` at top level). Under
  `-swift-version 6` without the `ApproachableConcurrency` feature, a `nonisolated async`
  function runs on the global pool, not on the caller's actor.
- **Recursion limits.** The main thread has an 8 MiB stack; tasks run on pool threads with
  512 KiB. A trial with a linked list of `final class` nodes (recursive build, recursive walk and
  the recursive ARC release) crashed at depth about 4 000 inside a `Task` and about 80 000 on the
  main thread. Binary-tree depths in the SPECs (about 20) are nowhere near either, but do not
  recurse over long lists inside tasks.
- **Trees.** `final class Node { let left: Node?; let right: Node? }` (ARC, freed when the last
  reference goes) or `indirect enum`. Both are idiomatic; `final class` is the usual choice for
  binary_trees.
- **No `-Ounchecked`, no `@inline(__always)` sprinkling, no `unsafe` pointer buffers**
  (`withUnsafeMutableBufferPointer`) unless the code would look odd without it; plain `[Int]`
  with `reserveCapacity` is the idiom.
