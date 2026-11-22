- **Cheby runs in 1.04 s, 1.05× Rust.** That is `cheby run` as a whole process. The `cheby build`
  executable takes 1.06 s. The two rows are 15th and 16th of 21, next to the languages that free
  node by node. Rust (991 ms) is just ahead. C++ (1.12 s), Odin (1.26 s) and Swift (1.66 s), which
  also counts references (ARC), are behind. Most tracing collectors lead: Java 255 ms, Go 612 ms,
  OCaml 703 ms (Cheby 1.47×), Gleam 747 ms (1.39×) and Erlang 792 ms (1.31×). Koka, the closest
  model to Cheby (Perceus over mimalloc), is the one reference-counted language far ahead, at 396 ms
  (Cheby 2.62×).
- **Peak RSS is 51.7 MB under `cheby run`, against 17.9 MB for Rust and 254 MB to 413 MB for the
  BEAM and the JVM.** 16.4 MB of it is the floor of every `cheby run` process, which carries the
  compiler and the JIT: that is what `hello_world` peaks at. The executable peaks at 57.8 MB,
  although its floor is only 3.5 MB. No run here explains why it peaks above `cheby run`. Go (37.7
  MB) and OCaml (46.6 MB), which use tracing collectors, peak below both rows.
- **The work matches the SPEC: one heap object per node, freed by its count (D-005).** The runtime's
  allocation counter (`CHEBY_RT_STATS=1`) shows one allocation per node at the test size. The SPEC
  requires one allocation and one free per node in every language, so those are not a cost of
  reference counting. What reference counting adds is small here: `check` borrows its tree, so the
  walk touches no counts, and one `drop` after `check` frees the whole tree, one decrement and one
  free per node (the program's MIR). Only that part is language design.
- **The runtime's own allocation and free path takes as much time as the compiled code.** A profile
  of the executable at the bench size puts 44% of the samples in the runtime's allocation and free
  code and 44% in the compiled `make` and `check`. In the runtime, `drain`, the loop that frees a
  tree node by node, takes 25% and `cheby_rt_alloc` 18%. mimalloc's own functions take about 6%
  (D-890). The runtime's share is current implementation. Koka, for comparison, frees each node
  inline while `check` walks it (see Koka's `impl.toml`).
- **Both rows are steady.** Ten timings span 1.03 s to 1.05 s for `cheby run` and 1.05 s to 1.07 s
  for the executable. The `cheby run` row includes its start-up, which is 7.5 ms here.
- **Outside Cheby, the allocator likely explains much of the order among the malloc/free
  languages.** Zig's nodes come from `std.heap.smp_allocator` and it runs in 504 ms, while Rust (991
  ms) and C++ (1.12 s) use the macOS system `malloc` (see Zig's `impl.toml`). No run swapped the
  allocator to confirm it. Koka's 396 ms comes from its bundled mimalloc together with freeing each
  node inline as `check` walks it (Koka's `impl.toml`).
