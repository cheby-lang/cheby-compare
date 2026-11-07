# hello_world

The smallest program. It prints `Hello, world!` and exits. There is no algorithm. The benchmark
measures what every program pays before it does any work: the cold compile time of the smallest
program and its start-up time.

## Purpose

- **What it measures.**
  - **Compile time**: the time to build this one-line program from a clean state, with the
    language's release build (the `build` and `clean` commands in `langs/<lang>.toml`). For
    languages without a build step (Python, Ruby) there is no compile time.
  - **Start-up time**: the median run time of the built program. Every size is `0`, so start-up is
    also the run time. It covers loading the executable or the VM, initialising the runtime and
    the standard library, writing one line and shutting down.
  - Peak memory and artifact size of the smallest program, which the runner records as usual.
- **Where languages differ.** AOT languages (Rust, C++, Zig, Odin, Go, Swift, Nim, OCaml, Koka)
  start in a few milliseconds, and their compile time is mostly the fixed cost of the compiler and
  linker. VM languages (JVM, CLR, BEAM, node) pay for starting the VM and loading classes or
  modules. Interpreters (Python, Ruby) pay for interpreter start-up and the import of their core
  modules. Clojure and Scala also load their language runtime on top of the JVM.
- **Expected for Cheby: a compile time near a small AOT build, start-up near other executables.**
  - Compile: `cheby build` compiles this one small module and links it with std's cached code. Most
    of its time is the link. The code is unoptimised, so it is not a like-for-like number against a
    release build (see Cheby measurement).
  - Start-up: the executable runs no front end. `cheby run`, the JIT row, reads the cached code of
    the program and of std, so it starts later than the executable and earlier than the JVM, CLR,
    BEAM, node and the interpreters.

## Cheby measurement

Cheby has two rows (see CONVENTIONS.md, Measurement). The `cheby-aot` row is measured like any AOT
language. The `cheby` row is the whole `cheby run` process with a warm cache, so it shows start-up
and no compile time. `cheby check` time is reported next to it as front-end time.

## Arguments

One argument, the size. It is always `0`. The program must ignore it: do not read, parse or
validate the arguments. A runtime that collects the command line on its own (the JVM, .NET, node)
is fine. The program just does not touch it.

## Algorithm

```text
print "Hello, world!"
exit 0
```

That is the whole program. Rules:

- Write the line once, with the language's ordinary way of printing a line to stdout: the one a
  fluent developer would write in a hello-world program (list below).
- No extra work: no argument parsing, no reading of the environment, no buffering set-up, no
  explicit flush unless the language needs one for the output to appear.
- No start-up tricks: no snapshots, no class-data-sharing archives built for this program, no
  prelinking, no stripping beyond the release default, no static linking unless it is the default.
  Use the release flags in `langs/<lang>.toml` unchanged.
- The program is the language's smallest normal project, built like every other benchmark. Do not
  give it a lighter build or run command than the other benchmarks use.
- Exit with status 0 and nothing on stderr.

## Output

Exactly one line, 14 bytes including the newline:

```text
Hello, world!
```

A capital `H`, a comma, one space, a lower-case `w`, an exclamation mark, then `\n`. No trailing
space, no `\r`, nothing before or after.

## Size 0

Size 0 is the only size. The program does the same thing at every size.

## Sizes

```toml
zero = ["0"]
test = ["0"]
bench = ["0"]
```

All three are identical, and so are `expected/zero.out`, `expected/test.out` and
`expected/bench.out`. The bench size is not scaled: the usual target of 0.5 to 1 second for Rust
does not apply here.

## Per-language guidance

Cheby's source follows the style of `cheby fmt`. Until M5, `cheby fmt` is not implemented, so
"fmt form" means matching the style of `../cheby/docs/examples` by hand.

Use the line-printing call a hello-world program uses in that language:

| Language   | Print call                                                               |
| ---------- | ------------------------------------------------------------------------ |
| Cheby      | `io::println("Hello, world!")` with `import std::io`                     |
| Gleam      | `io.println("Hello, world!")` with `import gleam/io`                     |
| Rust       | `println!("Hello, world!");`                                             |
| Go         | `fmt.Println("Hello, world!")`                                           |
| Zig        | the stdout writer's `print("Hello, world!\n", .{})`, returning its error |
| Odin       | `fmt.println("Hello, world!")`                                           |
| C++        | `std::cout << "Hello, world!\n";` with `#include <iostream>`             |
| Erlang     | `io:format("Hello, world!~n")`                                           |
| Python     | `print("Hello, world!")`                                                 |
| Java       | `System.out.println("Hello, world!");`                                   |
| TypeScript | `console.log("Hello, world!");`                                          |
| Swift      | `print("Hello, world!")`                                                 |
| C#         | `Console.WriteLine("Hello, world!");`                                    |
| Elixir     | `IO.puts("Hello, world!")`                                               |
| Scala      | `println("Hello, world!")` in a `@main` method                           |
| Clojure    | `(println "Hello, world!")` in `-main`, AOT-compiled with `:gen-class`   |
| Koka       | `println("Hello, world!")`                                               |
| OCaml      | `print_endline "Hello, world!"`                                          |
| Nim        | `echo "Hello, world!"`                                                   |
| Ruby       | `puts "Hello, world!"`                                                   |

Notes:

- **C++.** Use `<iostream>` and `std::cout`, not `<print>` and `std::println`. The choice moves
  this benchmark's main metric: with `clang++ -std=c++23 -O3`, `<print>` took 2.5 times the
  compile time and made a 3.4 times larger binary, at the same start-up. The other C++ benchmarks
  should print through `std::cout` too, so that this measures the fixed cost they pay.
- **BEAM (Erlang, Elixir, Gleam).** Run the compiled beams with `erl` as every other benchmark does,
  and stop all three the same way: call the entry function, then `halt(0)` at once, with no
  `init:stop()` and no `-s init stop` (which costs about 18% more here). The run command has the
  shape `erl -noshell -pa <beam dirs> -eval '<entry call>, halt(0).' -extra {args}`. Use only
  `-noshell`, `-pa`, `-eval` and `-extra`: the default boot script, and no `-mode`, `+S`, `-boot`
  or other emulator flags. The `-extra` is required. Without it, `erl` reads the size argument as
  more `-eval` text (`halt(0).0`), fails to evaluate it, exits 1 and writes `erl_crash.dump`.
  `-extra` passes the size as a plain argument, which a BEAM program reads with
  `init:get_plain_arguments()`. This program still ignores it. The halt does not drop the line:
  `io:format` and `IO.puts` return after the line is written.
- **JVM (Java, Scala, Clojure).** Plain `java` on the jar or class directory, default flags. No
  `-Xshare` archive made for this program, no `-XX:TieredStopAtLevel`, no AppCDS.
- **C#.** `dotnet` on the published dll, default settings. No ReadyToRun or native AOT unless the
  other C# benchmarks use it.
- **TypeScript.** `node` on the emitted JavaScript. The compile time is the `tsc` run. `node` on
  this machine's `PATH` is a vite-plus shim that adds about 8 ms to each start (about 30% of
  node's start-up), and `/opt/homebrew/bin/node` is v26, not the pinned node 24. So `run` calls the
  real node 24 binary by absolute path, `/Users/xikxp1/.vite-plus/js_runtime/node/24.22.0/bin/node`,
  or `env` puts its directory first on `PATH`. The reviewer checks `process.execPath`.
- **No shims or proxies.** No version manager or toolchain proxy (vp, volta, nvm, asdf, rustup)
  may sit between the runner and the compiler or runtime, for `build` and `run` alike. In this
  benchmark the fixed costs are the headline, and a proxy adds 10 to 30% to them. Rust's `cargo`
  and `rustc` on `PATH` are rustup proxies, so the Rust config should put the toolchain's own
  `bin` directory (`$(rustc --print sysroot)/bin`) first on `PATH` through `env`.
- **Zig.** Writing to stdout returns an error union, so `main` returns `!void` and propagates it.
  Use the writer the standard library offers for stdout in the pinned version, buffered or not as
  its hello-world example does, and flush it if it is buffered.
