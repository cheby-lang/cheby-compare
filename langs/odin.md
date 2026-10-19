# Odin: notes for implementers

Toolchain: Homebrew `odin` dev-2026-10 (`dev-2026-10:84bc3fc21`), LLVM 22 back end, Apple M3.
`setup/odin.sh` only checks that the formula, its `llvm@22` and the macOS SDK are there. There is
nothing to fetch and no cache to warm, so builds work offline.

## Project layout

One package per implementation, nothing else:

```text
benchmarks/<bench>/odin/
  main.odin        package main, with main :: proc()
  *.odin           optional, more files of the same package
  impl.toml        optional: libs, notes, or an override of a langs/odin.toml key
```

No manifest. `langs/odin.toml` builds every benchmark the same way, so you only write sources.

## Build and run by hand

The runner calls the real compiler, not `/opt/homebrew/bin/odin`, which is a bash wrapper (no
shims). The wrapper's only job is to put `llvm@22` first on `PATH`, because Odin links through
`clang` from `PATH`. `langs/odin.toml` does the same through `env`. By hand:

```sh
cd benchmarks/<bench>/odin
export PATH=/opt/homebrew/opt/llvm@22/bin:$PATH
/opt/homebrew/opt/odin/libexec/odin build . -o:speed -out:../../../build/odin/<bench>/main
../../../build/odin/<bench>/main <args>
```

Or use the runner:
`python3 runner/run.py verify -l odin -b <bench> --sizes zero,test,bench --diff`.

- `-o:speed` is the release level. The default, `-o:minimal`, is for development. Do not add
  `-no-bounds-check`, `-disable-assert`, `-o:aggressive` or `-microarch:native`, and do not put
  `#no_bounds_check` in the code. Bounds checks stay on, as in every default Odin build.
- Odin has no build cache and no daemon. Every build compiles the program and the `core:`
  packages it imports from source, as one LLVM module at `-o:speed`, then links. Hello world
  takes about 1.2 to 1.3 s on a busy machine, and a build without `clean` costs the same.
  `clean` removes `main` and a stray `main.o`, which Odin normally deletes after linking.
- `compile_large`: the generic `build` (`odin build .` in the project directory) works if
  `gen.py` puts `package main` at the project root and the modules in sub-directories, imported
  by relative path (`import "m0000"`).

## Third-party code

The rules allow a third-party library only for JSON, and Odin has `core:encoding/json`. The
json_roundtrip SPEC asks for it (`unmarshal` into structs, `marshal` with default options). So no
benchmark should need a dependency.

If one ever does: Odin has no package manager. `setup/odin.sh` would clone a pinned commit into
`build/odin-deps/<name>`, and the benchmark's `impl.toml` would override `build` with
`-collection:deps={root}/build/odin-deps` so the code can `import "deps:<name>"`. Name it in
`libs`. Do not vendor it into `benchmarks/`, where it would count as lines of code.

## APIs in this version (all checked)

- **Arguments.** `os.args` (`core:os`, the new `os` that replaced the old one and `os2`).
  `os.args[0]` is the program. `strconv.parse_int(os.args[1])` returns `(int, bool)`.
  `strconv.atoi` is deprecated.
- **Files.** `data, err := os.read_entire_file(path, context.allocator)`. The allocator argument
  is required now, and `err` is an `os.Error`, not a `bool`.
- **Output.** `fmt.println` writes to stdout with one `write` per call. For many lines, buffer
  them, either with a `bufio.Writer` over `os.to_writer(os.stdout)`, then `fmt.wprintln(...)` and
  a `defer bufio.writer_flush(&w)`, or with a `strings.Builder` printed once. Do whichever the
  SPEC's output guidance allows. Nothing may go to stderr.
- **JSON.** `json.unmarshal(data, &recs)` into structs, `json.marshal(recs)` returns `([]byte,
  Marshal_Error)`. Struct fields are written in declaration order with their own names, or the
  name in a `json:"name"` tag. Non-ASCII is written as raw UTF-8, not `\u` escapes, and `"` is
  escaped. Floats come out as `2.5000000000000000`, so keep floats out of marshalled data (the
  specs print floats as integers anyway). `json.Object` is a plain `map`, so a dynamic
  `json.Value` loses key order. Use structs. `json.parse(..., parse_integers = true)` keeps
  integers as `i64`.
- **Threads.** `thread.create_and_start_with_poly_data(arg, proc)` returns `^Thread`, then
  `thread.join(t)` and `thread.destroy(t)`. Each thread gets its own default context, with a heap
  allocator. A thread's stack is sized from `RLIMIT_STACK` (8 MiB here). That is virtual
  reservation and costs no RSS, but thousands of live threads reserve a lot of address space.
- **Channels.** `core:sync/chan` exists. `c, _ := chan.create(chan.Chan(int), context.allocator)`
  makes an unbuffered channel, and `chan.create(chan.Chan(int), cap, context.allocator)` a
  buffered one. Then `chan.send(c, x) -> bool`, `x, ok := chan.recv(c)` (`ok` is false once the
  channel is closed and drained), `chan.close(c)` and `chan.destroy(c)`. `chan.Chan(T, .Send)`
  and `chan.Chan(T, .Recv)` are the one-directional views.
- **Containers.** `core:container/lru` exists, but the lru_cache SPEC asks for `map[int]int` plus
  a `[dynamic]Node` linked by index. Use that. Also present: `container/queue`,
  `container/priority_queue`, `slice.sort` and `slice.sort_by` (`core:slice`), `strings.fields`.
- **Rounding.** `math.round` rounds half away from zero (`2.5 -> 3`, `-2.5 -> -3`), which is
  the contract's rule. Convert with `i64(math.round(x * 1e6))`.

## Integer widths and overflow

- `int` and `uint` are 64-bit. Use `i64` or `u64` when the SPEC names a width, and `u32` for
  32-bit wrapping hashes such as FNV-1a.
- Integer overflow wraps, signed and unsigned. That is defined behaviour in Odin, not a trap, so
  LCG and xorshift steps are plain `*`, `+`, `~` (xor) and `>>`. Checked: `max(i64) + 1` wraps
  to `min(i64)`. A shift by the bit width or more gives 0, or -1 for `>>` of a negative signed
  value, not UB. Division by zero panics.
- Constant expressions do not wrap. They are a compile error when the result does not fit the
  type (`~u32(0) * 3`), so write LCG multipliers as typed variables or `u64` literals that fit.
- Odin writes xor as `~`, and `&~` is "and not". There is no `^` operator, because `^T` is a
  pointer type and `p^` is a dereference.
- Mixing types needs explicit casts: `f64(i)`, `int(x)`. Untyped constants adapt.

## Recursion

The main thread has the 8 MiB default stack. Plain recursion one million frames deep ran fine in
an `-o:speed` build. Threads get 8 MiB too (above).

## Allocation

Use the default `context.allocator`, the heap, unless the SPEC says otherwise. For binary_trees
that means `new(Node)` and `free(node)`. Do not swap in an arena or the temp allocator for the
benchmark's own data: that counts as a hand-rolled allocation strategy. `delete` frees slices,
maps and dynamic arrays. Freeing at exit is not needed.
