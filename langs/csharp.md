# C# in cheby-compare

.NET SDK 10.0.402 with runtime 10.0.13 (C# 14, Roslyn 5.9), from Homebrew. The SDK lives in
`/opt/homebrew/opt/dotnet/libexec`. `/opt/homebrew/bin/dotnet` is a bash wrapper script around
the real muxer, so `langs/csharp.toml` puts `libexec` first on `PATH` and sets `DOTNET_ROOT`.
The base class library covers every benchmark: **System.Text.Json** for JSON, and **Tasks**
with **System.Threading.Channels** for concurrency. No third-party package is needed or allowed
(CONVENTIONS "Standard library first").

## Project layout

Every implementation is the `dotnet new console` project, named `main`:

```text
benchmarks/<bench>/csharp/
  main.csproj   copy benchmarks/hello_world/csharp/main.csproj unchanged
  Program.cs    top-level statements (`args` is in scope); more .cs files may sit next to it
  impl.toml     optional: libs, notes, or overrides of langs/csharp.toml keys
```

`main.csproj` is the template's: `OutputType Exe`, `net10.0`, `ImplicitUsings` and `Nullable`
enabled. The project must be called `main`. `run` executes `main.dll`, and `clean` deletes
`obj/main/release`. Do not add properties that change code generation or the runtime:
`Optimize`, `TieredCompilation`, `TieredPGO`, `PublishReadyToRun`, `PublishAot`,
`PublishTrimmed`, `InvariantGlobalization`, `ServerGarbageCollection`,
`ConcurrentGarbageCollection` or `AllowUnsafeBlocks`. Do not add a `runtimeconfig.template.json`
either. Start `Program.cs` with a `//` comment that says what the program does. Nothing is
written into the source directory, because all build output goes under `build/csharp/<bench>/`.

## Build, clean, run (langs/csharp.toml)

- `build`: `dotnet publish -c Release --artifacts-path {build}/artifacts -o {build}/out
  --disable-build-servers -nodeReuse:false -p:UseSharedCompilation=false`. This is a
  framework-dependent JIT build with no ReadyToRun or NativeAOT. MSBuild gets no reusable nodes,
  and csc runs as a fresh process instead of VBCSCompiler (the log says "using command line tool
  by design").
- `clean`: removes `{build}/out`, `{build}/artifacts/bin` and `{build}/artifacts/obj/main/release`.
  It keeps the restore outputs in `{build}/artifacts/obj/main/` (`project.assets.json` and the
  files next to it), and `~/.nuget/packages` is never touched. After a clean, the build's restore
  is a no-op ("No-Op restore") that needs no network, and csc recompiles only this program.
- `run`: `dotnet {build}/out/main.dll {args}`. `artifact`: `{build}/out/main.dll`.
- `warm_start`, `build_warm` and `warm_stop` cover the warm-compile row (CONVENTIONS
  "Measurement"). `build_warm` is the same publish without `--disable-build-servers`,
  `-nodeReuse:false` and `-p:UseSharedCompilation=false` (it passes `-nodeReuse:true
  -p:UseSharedCompilation=true`, the SDK defaults), so it writes the same `{build}/out/main.dll`
  that `run` uses. .NET has no command that only starts the server: the first build with servers
  allowed launches VBCSCompiler (and MSBuild worker nodes, if the build uses any), and they stay
  alive. So `warm_start` is one such build. The runner then does its warm-up builds, times
  `build_warm` after `clean`, and runs `warm_stop`, `dotnet build-server shutdown`, which stops
  VBCSCompiler and the MSBuild server. The cold `build` keeps its flags and starts no server.

Measured on hello_world on a busy machine: clean→build takes about 1.2 s, of which about 0.25 s
is the no-op restore. An up-to-date rebuild takes about 0.5 s and skips CoreCompile, so a build
near 1.2 s after `clean` shows that csc ran. A warm build takes about 0.6 s. Start-up is about
23 ms. No build server is left running afterwards; check with
`pgrep -fl 'VBCSCompiler|MSBuild.dll'`.

Warm compile, `measure --quick` (one warm-up build after `warm_start`), medians: hello_world
1.48 s cold, 0.64 s warm. compile_large: zero 1.49 s cold, 1.23 s warm; test 1.91 s cold, 0.95 s
warm; bench 3.96 s cold, 4.06 s warm (min 2.91 s, noisy). The server's own JIT warms up over
the first few builds, so the full run's three warm-up builds give steadier warm numbers than
`--quick`.

By hand, from the repository root:

```sh
python3 runner/run.py verify -l csharp -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py build -l csharp -b <bench>      # log: build/csharp/<bench>/build.log

# or by hand, in benchmarks/<bench>/csharp:
export DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec PATH=/opt/homebrew/opt/dotnet/libexec:$PATH
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
B=../../../build/csharp/<bench>
dotnet publish -c Release --artifacts-path $B/artifacts -o $B/out --disable-build-servers \
  -nodeReuse:false -p:UseSharedCompilation=false
dotnet $B/out/main.dll 10
```

Warnings, such as nullable ones, do not fail the build. Read them in `build.log` all the same.

## Adding a third-party package (not expected)

JSON is in the BCL (`System.Text.Json`), so no benchmark should need a package. If one ever
does:

1. Add `<ItemGroup><PackageReference Include="Name" Version="X.Y.Z" /></ItemGroup>` to that
   benchmark's `main.csproj`, with an exact version and no floating `*`.
2. Run `setup/csharp.sh`. It restores every `benchmarks/*/csharp/main.csproj` into
   `build/csharp/<bench>/artifacts` and downloads the package to `~/.nuget/packages`. From then
   on `build` works offline.
3. Add `libs = ["Name X.Y.Z"]` to `impl.toml`, and add `notes = "..."` if the choice needs a
   reason.

`clean` keeps the package and the restore outputs, so the timed build compiles only your code.

## Gotchas

- **Integer widths.** `int` is 32-bit, so use `long` or `ulong` wherever the spec says 64-bit,
  including loop counters and checksums that can grow. Arithmetic is unchecked in Release builds
  (`/checked-`), so `ulong` multiplication and addition wrap. That is what the LCG, xorshift and
  FNV generators want. A *constant* expression that overflows is a compile error: write
  `unchecked(...)`, or keep the constant in a `const ulong`. `>>` is arithmetic on signed types
  and logical on unsigned ones, and `>>>` (C# 11) is a logical shift on signed types. `(uint)x`
  truncates. Shift counts are masked (`x << 64 == x` for `ulong`).
- **`%` and `/`** truncate toward zero, so a negative left operand gives a negative remainder.
- **Float output.** `Math.Round(x)` defaults to **banker's rounding** (`Math.Round(2.5) == 2`).
  CONVENTIONS asks for half away from zero, so always write
  `(long)Math.Round(x * 1e9, MidpointRounding.AwayFromZero)`. Never print a `double`.
- **Culture.** This machine's current culture is `en-SE`. `string.Compare`, `CompareTo`, the
  default `List<string>.Sort()` and `OrderBy(s => s)` are culture-sensitive through ICU
  (`string.Compare("a", "B")` is -1, while ordinal gives 31). Sort strings with
  `StringComparer.Ordinal` or `string.CompareOrdinal`, and pass `StringComparison.Ordinal` to
  `IndexOf`, `StartsWith` and similar calls. Integers print without separators, but parse and
  format with `CultureInfo.InvariantCulture` when in doubt: `long.Parse(args[0],
  CultureInfo.InvariantCulture)`.
- **Arguments.** Top-level statements give you `args`, which does not include the program name.
  Size 0 must work and take the same code path.
- **Output.** `Console.Out` auto-flushes on every write, so it makes one syscall per
  `WriteLine`. That is fine for a few lines. For many lines, use
  `using var w = new StreamWriter(Console.OpenStandardOutput());` and `w.WriteLine(...)`, which
  flushes on dispose, or build a `StringBuilder` and write it once. `NewLine` is `"\n"` on macOS.
  Return from `Main`, or reach the end of the top-level statements, instead of calling
  `Environment.Exit`, which skips the `using` disposal and loses the buffered output.
- **Recursion limits.** The main thread has the process stack, 8 MB (`ulimit -s`). A simple
  recursive function reached about 260,000 frames. Thread-pool threads, which run every `Task`,
  have 1.5 MB, which overflowed at about 49,000 frames. A stack overflow kills the process, and
  it cannot be caught. Tree depths in binary_trees and recursive-descent JSON are far below
  this. Keep deep recursion off `Task.Run`, or use an explicit stack.
- **Collections.** The enumeration order of `Dictionary<K,V>` is not guaranteed, especially
  after removals, so sort the keys before printing. `CollectionsMarshal.GetValueRefOrAddDefault`
  is the idiomatic single-lookup counter update. For an LRU, `LinkedList<T>` plus a
  `Dictionary<K, LinkedListNode<T>>` is the standard library's building block.
  `Array.Sort` / `List.Sort` are introsort and not stable. Use a comparer that breaks ties when
  the spec fixes an order.
- **Structs vs classes.** Choose what a fluent developer would: a `record` or `class` for tree
  nodes (binary_trees must allocate them on the GC heap), and a `struct` or plain `double[]` for
  nbody bodies are both normal. Do not use `unsafe`, `stackalloc` tricks, `Span` gymnastics
  beyond everyday use, or `System.Runtime.Intrinsics`.
- **GC and runtime.** Keep the defaults: workstation concurrent GC, tiered JIT with OSR and
  Dynamic PGO. Do not call `GC.Collect` or set `GCSettings`. The program reads no environment
  variable. The runtime reading `DOTNET_*` on its own is fine.
- **JSON (System.Text.Json).** `JsonDocument` (read-only, pooled, needs disposal), `JsonNode`
  (mutable DOM) and `Utf8JsonReader`/`Utf8JsonWriter` all keep the document's property order.
  The default encoder escapes non-ASCII and HTML characters: `"é<x>"` serialises as
  `"é<x>"`. Check the spec's escaping rules. If it wants raw UTF-8, use
  `JavaScriptEncoder.UnsafeRelaxedJsonEscaping` (it still escapes some characters) or
  `JavaScriptEncoder.Create(UnicodeRanges.All)`, or write the string yourself. Default
  indentation is off, and `WriteIndented` uses 2 spaces. Read integers with `GetInt64()` and
  `TryGetInt64`, never through `double`. Reflection-based `JsonSerializer` works, since this is
  JIT and not trimmed.
- **Concurrency.** Use `Task.Run` / `async` and `await` on the default thread pool, with
  `Channel.CreateUnbounded<T>()` or `Channel.CreateBounded<T>(n)`. **`CreateBounded<T>(0)` is a
  rendezvous (unbuffered) channel in .NET 10**: `WriteAsync` completes only when a reader takes
  the item (checked here). Use it where a spec says unbuffered. Use `await
  reader.ReadAsync()`/`WriteAsync`, or `await foreach (var x in reader.ReadAllAsync())` after
  `writer.Complete()`. Never block a pool thread with `.Result` or `.Wait()` inside a task, which
  starves the pool. Join many tasks with `await Task.WhenAll(tasks)`. Do not change
  `ThreadPool.SetMinThreads`.
- **No `dotnet run`** anywhere, not in `run` and not in scripts. Run the published dll.
