# Scala: guide for implementers

Scala 3.10.0, compiled by `scala-cli` 1.18.0 (Homebrew `scala` and `scala-cli` formulas), run on
OpenJDK 27 (`/opt/homebrew/opt/openjdk`, keg-only). `langs/scala.toml` puts the JDK first on
`PATH`, sets `JAVA_HOME` (scala-cli's `--jvm system` needs it) and sets `COURSIER_MODE=offline`, so
a build only reads the Coursier cache (`~/Library/Caches/Coursier`). `setup/scala.sh` fills that
cache: the 3.10.0 compiler, scala-library, ujson 4.4.3, every `//> using dep` found in
`benchmarks/*/scala/*.scala`, and Bloop plus the sbt bridge for the warm-compile number. Run it
once, and again after adding a dependency.

## Project layout

One generic layout, set in `langs/scala.toml`. Group agents only write sources.

```text
benchmarks/<bench>/scala/
  main.scala      top-level `@main def main(...)`, no `package` line: compiles to class `main`
  Other.scala     optional; every .scala (and .java, .sc) file in the directory is compiled
  impl.toml       optional: libs, notes, or overrides of langs/scala.toml keys
```

- The run command is `java @{build}/java.args main {args}`, so the entry point must be a
  top-level `@main def main` (class `main`). Do not define any other top-level `main`.
- Start `main.scala` with a `//` comment saying what the program does.
- Take arguments as typed `@main` parameters: `@main def main(n: Int): Unit` or
  `@main def main(path: String, reps: Int): Unit`. Scala parses them; that is the idiomatic
  form. hello_world takes no parameter (`@main def main(): Unit`); the size argument is then
  ignored without error.
- No `//> using scala`, `//> using jvm` or `//> using option` directives: the version and flags
  come from the command line. `//> using dep` is the only directive to use (below).
- Put nothing else in the directory that scala-cli would treat as a source (`.java`, `.sc`).

## Build, clean, run (langs/scala.toml)

- `build`: `scala-cli compile --server=false --jvm system -S 3.10.0 --workspace {build}/ws
  -d {build}/classes -p .`, then sed turns the printed class path into `{build}/java.args`
  (`-cp {build}/classes:<scala-library and dependency jars in the Coursier cache>`). Wrapped in
  `sh -c '...'`, because hyperfine 2 refuses a timed command with unquoted `&&` or `>`.
  - `--server=false`: no Bloop daemon. scalac runs in a fresh JVM and always compiles the whole
    program (no zinc incremental state), so a build with or without `clean` takes the same time.
  - `--workspace {build}/ws`: `.scala-build/` and `.bsp/` go under `build/`, never into the
    source directory.
  - No compiler flags. Scala 3 has no optimiser; scalac's defaults are the release build.
- `clean`: removes `{build}/classes`, `{build}/ws`, `{build}/classpath`, `{build}/java.args`.
  The compiler and all jars stay in the Coursier cache.
- `run`: plain `java` on the class directory, default flags. No `-Xss`, `-Xmx`, `-XX:`, no CDS
  archive. Never `scala-cli run`.
- `artifact`: `{build}/classes` (the program's own classes; scala-library is not counted).
- Warm compile (CONVENTIONS "Measurement") is a second column next to the cold one:
  - `warm_start`: `scala-cli --power bloop start --jvm system` starts Bloop on the Homebrew JDK.
  - `build_warm`: the `build` command without `--server=false` and with `--bloop-jvm system`, so
    scala-cli compiles through the running Bloop instead of restarting it on another JVM. It
    writes the same `{build}/classes` and `{build}/java.args` that `run` uses. `clean` still wipes
    the workspace, so each timed build is a full compile by a warm compiler, not a zinc no-op.
  - `warm_stop`: `scala-cli --power bloop exit`. No Bloop process is left afterwards
    (`ps aux | grep -i bloop`).
  - The cold `build` keeps `--server=false` and never starts Bloop.

Measured on hello_world (busy machine): cold build 1.05 to 1.3 s (class files rebuilt each time,
nothing re-downloaded), start-up about 80 ms (Java's is about 20 ms; `println` loads
`scala.Console` and part of scala-library), peak RSS about 54 MB.

Cold against warm compile, from `measure --quick` (n=3, load average about 19, so rough): hello_world
1.09 s against 0.62 s (warm 0.42 to 0.76 s); compile_large M=1 2.35 s against 0.68 s, M=10 6.21 s
against 1.15 s, M=200 11.8 s against 7.4 s. On a quieter machine, warm hello_world was about 0.30 s.

## Building and running one benchmark by hand

```sh
python3 runner/run.py verify -l scala -b nbody --sizes zero,test,bench --diff
python3 runner/run.py build -l scala -b nbody      # build log: build/scala/nbody/build.log

# or manually, from benchmarks/nbody/scala:
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
export PATH=$JAVA_HOME/bin:$PATH COURSIER_MODE=offline
B=$PWD/../../../build/scala/nbody
scala-cli compile --server=false --jvm system -S 3.10.0 --workspace $B/ws -d $B/classes -p . > $B/classpath
sed -e "s|[^:]*/ws/\.scala-build/[^:]*|$B/classes|" -e "s|^|-cp |" $B/classpath > $B/java.args
java @$B/java.args main 1000
```

Compiler warnings and errors go to stderr, which the runner saves in `build.log`.

## Third-party dependency: ujson (json_roundtrip)

The Scala standard library has no JSON, so `json_roundtrip` may use ujson (com.lihaoyi; upickle's
JSON AST), which CONVENTIONS allows. Declare it at the top of `main.scala`:

```scala
//> using dep com.lihaoyi::ujson:4.4.3
```

That version is already in the cache (setup fetched it, with upickle-core 4.4.3 and geny 1.1.1);
the build puts it on the run class path through `java.args` automatically, no `impl.toml`
override needed. Record it in `benchmarks/json_roundtrip/scala/impl.toml`:

```toml
libs = ["ujson 4.4.3"]
notes = "ujson (com.lihaoyi) AST"
```

This flow was tested through the runner with a scratch benchmark. ujson facts: `ujson.read(s)`
takes a `String` (or a `java.nio.file.Path`); `ujson.Obj` keeps insertion order (a LinkedHashMap),
so a round trip keeps key order; numbers are `ujson.Num(Double)` (exact for 32-bit integers; read
them with `.num.toLong` / `.num.toInt`, and an integral `Num` is written without `.0`);
`ujson.write(v)` is compact, no spaces. Build an object in a given key order with
`ujson.Obj("a" -> 1, "b" -> "x")`.

To use another version or library: add the `//> using dep` line, run `./setup/scala.sh` (it
compiles every benchmark whose sources contain `//> using dep` online, once, filling the cache),
then build as usual. A build of an unfetched dependency fails with "not found: .../Coursier/...".
Never commit jars.

## Gotchas

- **Integer widths**: `Int` is 32-bit and `Long` 64-bit, signed, wrapping silently on overflow,
  which is what a 64-bit LCG or xorshift wants. Literals need `L` (`6364136223846793005L`). Use
  `>>>` for logical shifts, and `java.lang.Long.remainderUnsigned`, `divideUnsigned`,
  `compareUnsigned`, `toUnsignedString` where the SPEC treats a value as unsigned; mask 32-bit
  unsigned values with `& 0xFFFFFFFFL`. `Int * Int` overflows before widening: write
  `a.toLong * b`. Hex literals above `Int.MaxValue` need the `L` suffix.
- **Rounding floats**: `math.round(x: Double): Long` is Java's `Math.round`, half up
  (`math.round(-2.5) == -2`). Half away from zero is
  `if x < 0 then -math.round(-x) else math.round(x)`. Never `f"$x%.3f"` in output.
- **Output**: `println` goes through `Console.out`, a `PrintStream` that flushes on every line.
  For more than a few lines, build a `StringBuilder` and print once, or wrap `System.out` in a
  `java.io.PrintWriter(java.io.BufferedWriter(java.io.OutputStreamWriter(System.out)))` and
  flush at the end. Line ending is `\n`.
- **Recursion depth**: the default thread stack is 2 MB (no `-Xss` allowed). A tiny recursive
  function overflowed at depth 50,000 before the JIT compiled it and passed 100,000 after, so
  the limit is not stable. Keep non-tail recursion below about 10^4 (binary trees of depth ~20
  are fine). Self tail calls compile to a loop; annotate them with `@scala.annotation.tailrec`
  so the compiler checks it. Mutual recursion is not optimised.
- **Hot numeric code**: `Array[Double]`/`Array[Int]` and `while` loops are idiomatic Scala for hot
  loops (they compile to primitive arrays and plain loops). `for (i <- 0 until n)` is fine and
  usually inlined by the JIT, but a `while` is the predictable choice in tight inner loops.
  `final case class` with `Double` fields for records; `var` fields where the SPEC mutates in
  place (nbody).
- **Collections**: `mutable.HashMap` iteration order is unspecified: sort before printing
  (`m.toSeq.sortBy(...)`, or `sortWith` for mixed orders). `mutable.HashMap.getOrElse` +
  `update`, or `updateWith`, for counting. For LRU, `java.util.LinkedHashMap(cap, 0.75f, true)`
  with `removeEldestEntry` overridden, or `mutable.LinkedHashMap` with remove and re-insert.
  Boxed keys in generic collections are normal; third-party primitive collections are not allowed.
- **Strings**: `s.split("\\s+")` takes a regex and leaves a leading empty token when `s` starts
  with whitespace; `.strip` first or follow the SPEC's own word rule. Read files with
  `java.nio.file.Files.readString(java.nio.file.Path.of(path))` (or `scala.io.Source`, slower).
- **Concurrency**: use the JDK: virtual threads (`Thread.ofVirtual().start(() => ...)` then
  `join()`, or `java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor()` in a
  `scala.util.Using`), with `SynchronousQueue` / `ArrayBlockingQueue` / `LinkedBlockingQueue`
  (`put`/`take`) as channels. Scala lambdas convert to `Runnable` and `Callable` directly, but
  `executor.submit(() => ...)` is an ambiguous-overload compile error (both match); use
  `execute(() => ...)`, or annotate the lambda (`(() => x): Callable[Int]`).
  `scala.concurrent.Future` runs on a ForkJoinPool, not virtual threads; follow the SPEC's
  primitive. Keep default thread counts.
- **Unsafe warnings**: none seen with JDK 27 for lazy vals, collections, ujson or virtual threads.
  If stderr ever shows a `sun.misc.Unsafe` warning, report it; do not add JVM flags.
- **Size 0** goes through the same code path. JVM plus scala-library start-up is the cost there.
- **Warm-up**: no tricks (no repeated in-process runs, no `-XX` flags). JIT warm-up is part of
  the run time.
