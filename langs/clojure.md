# Clojure: guide for implementers

Clojure 1.12.6 on OpenJDK 27. The Clojure CLI (`clojure`, Homebrew formula `clojure`) resolves
`deps.edn`; the program is AOT-compiled to classes and run with plain `java`. The JDK is keg-only
(`/opt/homebrew/opt/openjdk/bin`); `langs/clojure.toml` puts it first on `PATH` through `env`.
`setup/clojure.sh` (idempotent) checks both, downloads Clojure and `clojure.data.json` into
`~/.m2`, AOT-compiles data.json once into `build/clojure-lib/data.json-2.5.2/`, and fills the
CLI's classpath cache for every `benchmarks/*/clojure/deps.edn`. Run it again after adding or
changing a `deps.edn`; after that every build works offline.

## Project layout

One generic layout, set in `langs/clojure.toml`. Group agents only write sources (and an
`impl.toml` when a library is used).

```text
benchmarks/<bench>/clojure/
  deps.edn        {:paths ["src"] :deps {org.clojure/clojure {:mvn/version "1.12.6"}}}
  src/main.clj    (ns main (:gen-class)) with (defn -main [& args] ...)
  src/...         optional extra namespaces that main requires (src/foo/bar.clj = foo.bar)
  impl.toml       optional: libs, notes, env (json_roundtrip)
```

Copy `benchmarks/hello_world/clojure/` as the starting point. The namespace must be `main`, with
`(:gen-class)`; the source path is always `src` (the build hard-codes it, `:paths` is for editors).

- `build` (one line in the toml, commented there):
  1. `clojure -Srepro -Sdeps "$(cat deps.edn)" -Spath`, run inside `{build}`, gives the jar
     classpath. Running it there keeps the CLI's cache in `CLJ_CACHE`
     (`build/clojure-cache/`), so no `.cpcache/` appears in the source tree. Warm, it costs
     about 10 ms and needs no network. `-Srepro` ignores `~/.clojure/deps.edn`.
  2. Writes `{build}/run.args`, a java argument file holding `-cp {build}/classes:<libs>:<jars>`.
  3. `java -Dclojure.compile.path={build}/classes -cp src:{build}/classes:<libs>:<jars>
     clojure.lang.Compile main`: one cold JVM, Clojure's own AOT entry point. It compiles `main`
     and every program namespace it requires. Default compiler options: no direct linking, no
     `*unchecked-math*` set globally. No daemon, no nREPL.
- `clean`: `rm -rf {build}/classes {build}/run.args`. Clojure's own classes come AOT-compiled in
  its jar; `~/.m2`, `build/clojure-cache/` and `build/clojure-lib/` are kept.
- `run`: `java @{build}/run.args main {args}`. Plain `java`, default flags (no `-Xss`, `-Xmx`,
  `-XX:`, no CDS archive). `@file` is the java launcher's own argument-file syntax.
- `artifact`: `{build}/classes` (the program's classes only, not the 4 MB Clojure jar).

hello_world measured here (busy machine): clean build 420 to 610 ms (5 runs, about 540 ms; the
classes really are rebuilt each time, and only `main*.class` is written), start-up about 240 ms
(Clojure loads `clojure.core` on every start, on top of the JVM's ~40 ms).

## Building and running one benchmark by hand

```sh
cd benchmarks/nbody/clojure
export PATH=/opt/homebrew/opt/openjdk/bin:$PATH CLJ_CACHE=$PWD/../../../build/clojure-cache
B=$PWD/../../../build/clojure/nbody; mkdir -p $B/classes
jars=$(cd $B && clojure -Srepro -Sdeps "$(cat deps.edn)" -Spath | tr : '\n' | grep '^/' | paste -sd: -)
java -Dclojure.compile.path=$B/classes -cp "src:$B/classes:$jars" clojure.lang.Compile main
java -cp "$B/classes:$jars" main 1000
```

Or through the runner (build, every size, the diff); it writes `build/clojure/<bench>/build.log`:

```sh
python3 runner/run.py verify -l clojure -b nbody --sizes zero,test,bench --diff
```

For a quick REPL experiment: `clojure -Srepro -M -e '(+ 1 2)'` from the repository root.

## Third-party dependency: clojure.data.json (json_roundtrip)

The one library allowed (CONVENTIONS). Three places:

1. `deps.edn`:
   `:deps {org.clojure/clojure {:mvn/version "1.12.6"} org.clojure/data.json {:mvn/version "2.5.2"}}`
2. `impl.toml`:

   ```toml
   libs = ["clojure.data.json 2.5.2"]
   notes = "..."
   env = { CLJ_AOT_LIBS = "{root}/build/clojure-lib/data.json-2.5.2" }
   ```

   Libraries ship as source; AOT-compiling `main` would recompile every library namespace it
   requires into `{build}/classes` on every build (about 0.7 s for data.json), and `clean` would
   throw that away each time. `CLJ_AOT_LIBS` puts the classes `setup/clojure.sh` compiled once in
   front of the jars, so Clojure loads them and compiles only the program (tested: the build
   then writes only `main*` classes). Forgetting it still works, just with a slower build.
3. Run `setup/clojure.sh` once, so the new `deps.edn` is resolved and cached.

data.json facts (checked with 2.5.2): `json/read-str` gives `Long` for integers, `Double` for
decimals, string keys unless `:key-fn keyword`, and maps that are `PersistentArrayMap` up to 8 keys
and hash maps beyond, so key order is not a guarantee: build output records as `array-map` or a
`defrecord` in the SPEC's order. `json/write-str` is compact, escapes `/` as `\/` and non-ASCII as
`\uXXXX` by default (`:escape-slash false`, `:escape-unicode false` turn that off).

Any other library would need its own AOT step in `setup/clojure.sh` (copy the data.json block).
The `clojure-coreasync` variant is a separate id with its own config.

## Gotchas

- **Flushing**: `println` writes to `*out*`, which flushes on every newline by default
  (`*flush-on-newline*` is true): slow for many lines. For bulk output, build one string
  (`clojure.string/join`, a `StringBuilder`) and print it once, or `(binding [*flush-on-newline*
  false] ...)`. Then you **must** call `(flush)` before `-main` returns: tested, the output is
  lost without it.
- **Futures keep the JVM alive**: `future`, `pmap`, `send`/agents use a non-daemon thread pool, and
  the JVM waits about 60 s after `-main` returns (tested: 60.25 s). Call `(shutdown-agents)` at the
  end of `-main` if any of them ran. Virtual threads (`Thread/startVirtualThread`,
  `Executors/newVirtualThreadPerTaskExecutor`) are daemon threads and do not have this problem.
- **Recursion depth**: the default 2 MB stack overflows a simple non-tail recursion between 8,000
  and 10,000 frames when the code is still interpreted (cold JVM); later, JIT-compiled frames go
  deeper, so it is unpredictable. Keep real recursion depth under about 5,000 (tree depth is fine)
  and use `loop`/`recur` or `reduce` for iteration. `recur` is the only tail call; there is no
  general TCO. No `-Xss` flag is allowed.
- **Integer widths**: integer literals and arithmetic are 64-bit `long`. `+ - * inc dec` **throw**
  `ArithmeticException: long overflow` instead of wrapping. For LCG/xorshift/FNV hashing use
  `unchecked-add`, `unchecked-multiply`, `unchecked-subtract`, `unchecked-inc` (or
  `(set! *unchecked-math* true)` at the top of the file, which makes the ordinary operators wrap on
  primitive longs only). `/` on integers gives a `Ratio` (`(/ 7 2)` is `7/2`): use `quot`, `rem`
  (sign of dividend) or `mod` (sign of divisor). Bit ops: `bit-and`, `bit-or`, `bit-xor`,
  `bit-shift-left`, `bit-shift-right` (arithmetic), `unsigned-bit-shift-right` (logical). Unsigned
  values: `Long/remainderUnsigned`, `Long/compareUnsigned`, `Long/toUnsignedString`; 32-bit masks
  with `(bit-and x 0xFFFFFFFF)`. Literals over `Long/MAX_VALUE` become `BigInt` (`N`).
- **Boxing and reflection**: put `(set! *warn-on-reflection* true)` after the `ns` form; the build
  log then shows every reflective call, which is very slow in a hot loop. Fix them with type hints
  (`^String`, `^longs`, `^doubles`, `^java.util.HashMap`). In hot numeric code hint fn arguments and
  returns `^long` / `^double` (a primitive fn takes at most 4 arguments), and use `loop` locals,
  which stay primitive. `(set! *unchecked-math* :warn-on-boxed)` reports boxed arithmetic.
  `defrecord` fields can be hinted `^double` for nbody-style records.
- **Mutable arrays**: idiomatic for the in-place benchmarks (fannkuch): `(long-array n)`,
  `(double-array n)`, `aget`/`aset`/`alength` with `^longs`/`^doubles` hints (`aset` on a hinted
  array is primitive; `aset-long` is slower). Clojure 1.12 also has `long/1` array class syntax.
  Transients (`transient`, `conj!`, `assoc!`, `persistent!`) for building big collections.
- **Rounding floats**: `Math/round` rounds half up (`(Math/round -2.5)` is `-2`). Half away from
  zero: `(if (neg? x) (- (Math/round (- x))) (Math/round x))`, a `long`. Never print a double.
- **Arguments and files**: `(Long/parseLong (first args))`; `args` is a seq of strings (nil when
  empty). Files: `(slurp path)`, or `java.nio.file.Files/readAllBytes`. Clojure 1.12 allows
  `Long/parseLong` and `String/.length` as plain functions (`(map Long/parseLong args)`).
- **Strings and maps**: `clojure.string/split` takes a regex and drops trailing empty strings; for
  whitespace use `(clojure.string/split (clojure.string/trim s) #"\s+")` or a hand scan if the SPEC
  defines its own word rule. Map iteration order is unspecified: `sort-by` / `sort` before
  printing. `frequencies` exists; `java.util.HashMap` is fine where a mutable map is idiomatic.
  For LRU, `java.util.LinkedHashMap` with access order (proxy `removeEldestEntry`), or a
  persistent map plus an ordered structure.
- **Concurrency** (stdlib row): JDK virtual threads, `(Thread/startVirtualThread f)` and `.join`,
  or `(Executors/newVirtualThreadPerTaskExecutor)` in `with-open`; channels are
  `java.util.concurrent.SynchronousQueue` (rendezvous) or `ArrayBlockingQueue`/
  `LinkedBlockingQueue` with `.put`/`.take` (hint `^SynchronousQueue` to avoid reflection).
  `promise`/`deliver` work across virtual threads. Keep the default carrier count.
- **Size 0**: same code path; loops run zero times. Start-up (~240 ms) is the cost at size 0.
- **Warm-up**: no tricks (no in-process repetition, no JVM flags). JIT warm-up is part of the run.
