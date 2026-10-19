# Java: guide for implementers

OpenJDK 27 from Homebrew (`openjdk` formula, keg-only, `/opt/homebrew/opt/openjdk/bin`).
`langs/java.toml` puts that directory first on `PATH` through `env`, so commands say plain `java`
and `javac`. Never call `/usr/bin/java` (a macOS stub). `setup/java.sh` checks the JDK and fetches
the Jackson jars (the one third-party library, for `json_roundtrip`) from Maven Central into
`build/java-lib/`, checking each jar's SHA-1. Run it once; after that every build works offline.

## Project layout

One generic layout, set in `langs/java.toml`. Group agents only write sources.

```text
benchmarks/<bench>/java/
  Main.java       class Main, default package (no `package` line), public static void main
  Other.java ...  optional extra top-level classes; every *.java in the directory is compiled
  impl.toml       optional: libs, notes, or an override of build/run (json_roundtrip)
```

- `build`: `mkdir -p {build}/classes && javac -d {build}/classes *.java`. One cold `javac`
  process. javac has no optimisation flags and no daemon; the JIT optimises at run time. Do not
  add flags.
- `clean`: `rm -rf {build}/classes`. The JDK classes live in its runtime image and the Jackson
  jars in `build/java-lib/`, both outside `{build}`, so `clean` only drops this program's classes.
- `run`: `java -cp {build}/classes Main {args}`. Plain `java` on the class directory, default
  flags: no `-Xss`, `-Xmx`, `-XX:` options, no CDS/AOT cache made for the program.
- `artifact`: the `{build}/classes` directory (`{build}/app`, classes plus jars, for json_roundtrip).
- Prefer a single `Main.java`, with nested `static` classes/records for helpers. Extra files are
  fine when a fluent developer would split them.

hello_world measured here (busy machine): clean build about 200 ms (5 runs, 200 to 215 ms, the
class file really is rebuilt each time), run about 20 ms.

## Building and running one benchmark by hand

```sh
export PATH=/opt/homebrew/opt/openjdk/bin:$PATH
cd benchmarks/nbody/java
mkdir -p ../../../build/java/nbody/classes
javac -d ../../../build/java/nbody/classes *.java
java -cp ../../../build/java/nbody/classes Main 1000
```

Or through the runner (does build, every size, and the diff):

```sh
python3 runner/run.py verify -l java -b nbody --sizes zero,test,bench --diff
```

The runner writes `build/java/<bench>/build.log` with javac's output when a build fails.

## Third-party dependency: Jackson (json_roundtrip)

The JDK has no JSON API, so `json_roundtrip` uses Jackson databind 3 (CONVENTIONS allows Jackson).
`setup/java.sh` downloads exactly these jars into `build/java-lib/`:

- `tools.jackson.core:jackson-databind:3.2.3`
- `tools.jackson.core:jackson-core:3.2.3`
- `com.fasterxml.jackson.core:jackson-annotations:2.22` (Jackson 3 keeps annotations on the 2.x
  group id)

Jackson 3 packages are `tools.jackson.core.*` and `tools.jackson.databind.*` (not
`com.fasterxml.jackson.*`, which is Jackson 2). Its exceptions are unchecked
(`JacksonException`), so no `throws IOException` is needed. Use `JsonMapper.builder().build()` or
`new ObjectMapper()`, `readTree`, `JsonNode`/`ObjectNode`/`ArrayNode`, and `writeValueAsString`.
Check the SPEC's number and key-order rules against Jackson's defaults (for example how it reads
big integers and doubles, and whether it keeps object key order; `ObjectNode` keeps insertion
order).

`benchmarks/json_roundtrip/java/impl.toml` copies the jars next to the classes, so `{build}/app`
is the deployable form and its artifact size counts Jackson (as serde_json counts in Rust's
binary). This shape was tested through the runner. Quote the wildcard so `sh` does not expand it;
`java`/`javac` expand `dir/*` to the jars in it:

```toml
libs = ["jackson-databind 3.2.3", "jackson-core 3.2.3", "jackson-annotations 2.22"]
build = 'mkdir -p {build}/app/classes {build}/app/lib && cp "{root}"/build/java-lib/*.jar {build}/app/lib/ && javac -d {build}/app/classes -cp "{build}/app/lib/*" *.java'
clean = "rm -rf {build}/app/classes"
run = 'java -cp "{build}/app/classes:{build}/app/lib/*" Main {args}'
artifact = "{build}/app"
```

To add another jar (no other benchmark should need one), add a line to `JARS` in
`setup/java.sh` (group path, artifact, version) and run it again. Never commit jars.

## Gotchas

- **Arguments**: `Integer.parseInt(args[0])` (or `Long.parseLong`). File arguments arrive as an
  absolute path: `Files.readString(Path.of(args[1]))` or `Files.readAllBytes`.
- **Integer widths**: `int` is 32-bit, `long` 64-bit, both signed and wrapping on overflow (no
  exception), which is what a 64-bit LCG or xorshift wants. Use `long` for 64-bit generators,
  `>>>` for logical right shifts, and `Long.remainderUnsigned` / `Long.divideUnsigned` /
  `Long.compareUnsigned` / `Long.toUnsignedString` wherever the SPEC treats the value as unsigned.
  Mask with `& 0xFFFFFFFFL` for 32-bit unsigned values. Watch `int * int` overflowing before it is
  widened: write `(long) a * b`.
- **Rounding floats**: the contract rounds half away from zero, but `Math.round` rounds half up
  (`Math.round(-2.5) == -2`). Use `x < 0 ? -Math.round(-x) : Math.round(x)` (returns `long`), or
  `(long) Math.rint(...)` only where the SPEC's ties cannot occur. `Math.round` on positives is
  exact (no `floor(x + 0.5)` bug).
- **Output**: `System.out` is a `PrintStream` that flushes on every `println`. For more than a few
  lines, build the output in a `StringBuilder` and print once, or wrap stdout in a
  `PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)))` and flush it at the end.
  `println` writes `\n` on macOS (it uses `line.separator`). Do not use `printf("%.3f")` for
  floats; print the rounded `long`.
- **Recursion depth**: the default thread stack is 2 MB here (`ThreadStackSize=2048`), main
  thread and platform threads alike. A tiny recursive function went past 64,000 frames but not
  128,000, in a platform thread and in a virtual thread too. Recursion of depth around 10^4 is
  safe; beyond that, loop. No `-Xss` flag is allowed.
- **Heap and GC**: default G1, max heap 4 GB (a quarter of RAM), compact object headers on by
  default in JDK 27. Peak RSS includes the JVM's own ~40 MB.
- **Collections**: `HashMap` iteration order is not part of any output contract; sort before
  printing (`entrySet().stream().sorted(...)` or a `List` and `List.sort`). For LRU,
  `new LinkedHashMap<>(cap, 0.75f, true)` (access order) with `removeEldestEntry` overridden.
  Boxed `Integer`/`Long` keys are idiomatic; primitive-specialised third-party collections are not
  allowed.
- **Strings**: `String.split` takes a regex and drops trailing empty strings. For whitespace
  splitting, `s.split("\\s+")` leaves a leading empty token when `s` starts with whitespace;
  `strip()` first, or scan by hand if the SPEC defines its own word rule.
- **Concurrency**: virtual threads are the idiomatic lightweight task:
  `Thread.ofVirtual().start(r)` + `join()`, or
  `try (var ex = Executors.newVirtualThreadPerTaskExecutor()) { ... }` (its `close()` waits for
  every task). Channels: `SynchronousQueue` (rendezvous, unbuffered) or
  `ArrayBlockingQueue`/`LinkedBlockingQueue` (buffered), `put`/`take`. They throw the checked
  `InterruptedException`, so `main` can declare `throws Exception`. Carrier threads default to the
  core count (8 here); keep the default. `synchronized` no longer pins a virtual thread (JDK 24+).
- **Records and switch**: Java 27 has records, sealed interfaces, pattern-matching `switch`, `var`
  and unnamed variables (`_`). Use them where they read naturally. Avoid preview features
  (`--enable-preview` would change the build flags).
- **Size 0**: everything goes through the same code path; loops just run zero times. The JVM
  start-up is the cost at size 0.
- **Warm-up**: no tricks (no repeated in-process runs to warm the JIT, no `-XX` flags). The JIT
  warm-up is part of Java's run time.
