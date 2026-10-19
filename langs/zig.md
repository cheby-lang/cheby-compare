# Zig: notes for implementers

Zig 0.17.0 from Homebrew (`/opt/homebrew/bin/zig`). The std source is in
`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std` (`zig env` prints it). The API changed a lot in
0.15 to 0.17 (`std.Io`, unmanaged containers, the new `Writer`). Code from blog posts or older
answers is usually wrong. Check the std source.

## Project layout

Every benchmark uses the same layout, and `langs/zig.toml` builds it with no `impl.toml`:

```text
benchmarks/<bench>/zig/
  src/main.zig        the program; other files sit next to it and are pulled in with @import("x.zig")
  impl.toml           optional: libs = [...], notes = "...", or overridden keys
```

There is no `build.zig` and no `build.zig.zon`. Plain `zig build-exe` is Zig's smallest normal
project, and `zig build` would compile and run a build runner as well on every cold build.

```toml
env   = { ZIG_GLOBAL_CACHE_DIR = "{root}/build/zig-global-cache" }
build = "zig build-exe -O ReleaseFast --cache-dir {build}/zig-cache --name main -femit-bin={build}/main src/main.zig"
clean = "rm -rf {build}/zig-cache {build}/main"
run   = "{build}/main {args}"
```

- `-O ReleaseFast` is the release mode. No `-mcpu=native` (the default target is the baseline
  `aarch64-macos` CPU), no `-fstrip`, no `-fsingle-threaded`, no LTO flags.
- The **global cache** (`build/zig-global-cache`, warmed by `setup/zig.sh`) holds compiler_rt and
  the libSystem stubs, which Zig builds once per target and mode. Zig has no precompiled std: std
  is compiled from source into every program, so `clean` makes the next build compile the whole
  program and the parts of std it uses. That is the intended compile time.
- **No daemon.** `zig build-exe` is one process and leaves nothing running.
- A clean build of hello_world takes about 5.5 s on this (busy) machine: LLVM in ReleaseFast
  over `std.Io` and `std.fmt`. A rebuild without `clean` also recompiles, because `-femit-bin`
  skips the whole-program cache check. That is expected.
- compile_large uses the same command in the generated project directory (`src/main.zig` plus
  `src/m0000.zig` and so on), with `--cache-dir {build}/zig-cache`, as its SPEC asks.

## Building and running one benchmark by hand

```sh
cd benchmarks/nbody/zig
export ZIG_GLOBAL_CACHE_DIR=$PWD/../../../build/zig-global-cache   # or omit it and use ~/.cache/zig
zig build-exe -O ReleaseFast --cache-dir /tmp/z/zig-cache --name main -femit-bin=/tmp/z/main src/main.zig
/tmp/z/main 1000
```

The runner does this for you:

```sh
python3 runner/run.py verify -l zig -b nbody --sizes zero,test,bench --diff
```

Build errors go to `build/zig/<bench>/build.log`. A quick compile check without code generation:
`zig build-exe -fno-emit-bin src/main.zig` (this is much faster than a ReleaseFast build).

## The skeleton every program starts from

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa; // see "Allocators" below
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const n = try std.fmt.parseInt(u32, args[1], 10);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{d}\n", .{n});
    try stdout.flush(); // the writer is buffered: without this nothing appears
    _ = gpa;
}
```

- `main(init: std.process.Init)` is what `zig init` generates in 0.17. `init` carries `io`
  (an `std.Io.Threaded`), `gpa`, `arena` (freed at exit) and `minimal.args`.
- Output goes through a buffered `std.Io.File.Writer`. Always `flush()` before returning, and
  before `std.process.exit(0)`, which does not flush.
- `std.debug.print` writes to **stderr**. Do not use it for output.
- Reading a file: `try std.Io.Dir.cwd().readFileAlloc(init.io, path, gpa, .unlimited)`.

## Allocators

- `init.gpa` is `std.heap.c_allocator` (libc malloc) in ReleaseFast on macOS, because macOS
  executables always link libSystem (`builtin.link_libc` is true). `smp_allocator` is chosen only
  when libc is not linked. In Debug it is a leak-checking safe allocator.
- **binary_trees names `std.heap.smp_allocator`** explicitly. Use it there, not `init.gpa`.
- For the other benchmarks `init.gpa` is fine. Do not use an arena where the SPEC frees memory.

## Containers and APIs (0.17)

- `std.ArrayList(T)` is unmanaged: `var xs: std.ArrayList(u32) = .empty;`,
  `try xs.append(gpa, x)`, `xs.deinit(gpa)`. `initCapacity(gpa, n)`, `items` is the slice.
- `std.AutoHashMap(K, V)` and `std.StringHashMap(V)` still carry their allocator
  (`.init(gpa)`); `getOrPut` for counting. The `Unmanaged` variants take `gpa` per call.
  **lru_cache:** the hash map keeps tombstones and never rehashes at constant size; call
  `map.rehash()` every `capacity` removals, as its SPEC says.
- Sorting: `std.mem.sort(T, slice, ctx, lessThan)` (stable) or `std.mem.sortUnstable`.
- JSON: `std.json.parseFromSlice(T, gpa, bytes, .{})` returns `Parsed(T)` (call `deinit`), and
  `std.json.Stringify.value(v, .{}, writer)` or `std.json.Stringify.valueAlloc(gpa, v, .{})`
  write compact JSON by default (`.whitespace = .minified`). No third-party library is needed.
- Concurrency: there is **no `std.Thread.Mutex` or `std.Thread.Condition`** in 0.17. Blocking
  primitives are in `std.Io` and take `io`: `std.Io.Mutex` (`lock(io)`, `unlock(io)`),
  `std.Io.Condition`, `std.Io.Queue(T)` (`.init(&buffer)`, `putOne(io, x)`, `getOne(io)`, a
  zero-length buffer is a rendezvous), `std.Io.Group` (`group.concurrent(io, f, .{args})`,
  `group.await(io)`). `std.Thread.spawn(.{}, f, .{args})` and `join()` still exist. Follow the
  primitive each concurrency SPEC names.

## Integers and floats

- Pick explicit widths: `u64` for LCG and xorshift state, `i64` or `u64` for checksums.
  Overflow is a panic in Debug and undefined behaviour in ReleaseFast, so wrapping arithmetic must
  use `+%`, `-%`, `*%` (and `<<` needs a `u6` shift amount for `u64`: `@as(u6, k)` or `@intCast`).
- `/` and `%` on signed runtime integers are compile errors. Use unsigned types, or `@divTrunc`,
  `@divFloor`, `@rem`, `@mod` as the SPEC means.
- Mixing widths needs explicit casts: `@intCast` (checked in safe modes), `@truncate`, `@as`.
  Float to int is `@intFromFloat`, int to float `@floatFromInt`.
- The output rule `round(x * 10^k)`, half away from zero, is `@round` (it rounds half away from
  zero), then `@intFromFloat` into an `i64`.
- Zig does not contract `a * b + c` into an FMA unless you write `@mulAdd`. Do not use it.
- Format with `{d}` for numbers, `{s}` for strings. `{}` on a slice of `u8` is a compile error.

## Stacks and recursion

- The main thread stack is the macOS default, 8 MB (`ulimit -s`). Threads from `std.Thread.spawn`
  and from `std.Io.Threaded` get 16 MB by default (`std.Thread.SpawnConfig.default_stack_size`).
- LLVM turns simple tail recursion into loops in ReleaseFast, but nothing guarantees it. Write
  loops where the SPEC's algorithm is a loop. binary_trees recursion depth is the tree depth, so
  it is no problem.

## Adding a third-party module (not expected to be needed)

`zig build-exe` takes extra modules on the command line. Each `-M` defines a module, and the
flags before it (`-O`, `--dep`) apply to that module:

```sh
zig build-exe -O ReleaseFast --dep lib -Mmain=src/main.zig -O ReleaseFast -Mlib=<path>/root.zig \
  --cache-dir {build}/zig-cache --name main -femit-bin={build}/main
```

`src/main.zig` then does `@import("lib")`. Fetch the package in `setup/zig.sh` with
`zig fetch <tarball-url>` (it prints a hash and unpacks into `$ZIG_GLOBAL_CACHE_DIR/p/<hash>/`),
then put the full `build` line in that benchmark's `impl.toml` with the `p/<hash>` path written
via `{root}/build/zig-global-cache/p/<hash>/...`, and list it under `libs`. The build then works
offline. Note that Zig compiles such a module from source on every build, like std.
