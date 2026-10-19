- **Cheby runs ≈ 1.33 s, 17th of 20 and 1.34× Rust.** That puts it next to the languages that free
  node by node: Rust (991 ms), C++ (1.12 s) and Odin (1.26 s) are just ahead, and Swift, also
  reference counted (ARC), is behind at 1.66 s. Most tracing collectors lead: Java 255 ms, Go
  612 ms, OCaml 703 ms (Cheby 1.89×), Gleam 747 ms (1.77×) and Erlang 792 ms (1.67×). Elixir, at
  989 ms, is level with Rust. Koka, the closest model to Cheby (Perceus over mimalloc), is the one
  reference-counted language far ahead, at 396 ms (Cheby 3.35×).
- **Peak RSS is 52.6 MB, against 17.9 MB for Rust and 254 MB to 413 MB for BEAM and JVM.** 18.9 MB
  of Cheby's is the floor every `cheby run` process has, since it carries the compiler and the JIT:
  that is what `hello_world` peaks at. Without it Cheby would be at about 34 MB, still almost twice
  Rust and C++ (17.7 MB). Go (37.7 MB) and OCaml (46.6 MB), which use tracing collectors, peak
  below Cheby's total.
- **The work matches the SPEC: one heap object per node, freed by its count (D-005).** The runtime's
  allocation counter (`CHEBY_RT_STATS=1`) shows one allocation per node at the test size. The SPEC
  requires one allocation and one free per node in every language, so those are not a cost of
  reference counting. What reference counting adds is small here: `check` borrows its tree, so the
  walk touches no counts, and one `drop` after `check` frees the whole tree, one decrement and one
  free per node (the program's MIR). Only that part is language design.
- **Most of the time goes to the runtime's own allocation and free path, not to mimalloc.** A
  profile at depth 19 puts most samples in `alloc_from`, `init_object`, `drain` and `shape_of` in
  `crates/cheby_runtime/src/alloc.rs`, and only a small share in mimalloc's functions (D-890).
  Allocating does a budget check, a per-fiber block-cache lookup through thread-local storage and
  per-domain accounting. Freeing looks up each object's layout and walks a worklist. That is current
  implementation, which M3 and later may change. Koka, for comparison, frees each node inline while
  `check` walks it (see Koka's `impl.toml`).
- **The run time is an estimate, but a good one here.** It is the bench run minus a size-0 run
  (≈ 9.6 ms), under 1% of the total, and the ten runs span only 1.31 s to 1.34 s.
- **Outside Cheby, the allocator likely explains much of the order among the malloc/free
  languages.** Zig's nodes come from `std.heap.smp_allocator` and it runs in 504 ms, while Rust
  (991 ms) and C++ (1.12 s) use the macOS system `malloc` (see Zig's `impl.toml`). No run swapped
  the allocator to confirm it. Koka's 396 ms comes from its bundled mimalloc together with freeing
  each node inline as `check` walks it (Koka's `impl.toml`).
