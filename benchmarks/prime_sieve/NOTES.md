- **Cheby has the fastest row, but at this size it ties with Go.** Its estimated run time is
  ≈ 20 ms [17 ms–23 ms], and the whole process takes 31 ms. Go takes 28 ms [19 ms–34 ms],
  including 1.8 ms of start-up, so Go is ahead on whole-process time. As the SPEC says, both rows
  are dominated by start-up and noise, so they should not be ranked against each other. The
  rust-tokio variant takes 34 ms. Every other language is far behind. Swift takes 98 ms (4.95×
  Cheby's estimate), Java 207 ms (10.5×), the BEAM rows 238 ms to 272 ms (12.0× to 13.8×), Rust
  538 ms (27.2×) and OCaml's systhreads 4.57 s (231×).
- **Capacity-0 channels let the pipeline run on several cores.** Each handoff works as in
  ping_pong: the value goes straight into the parked receiver's wait node, and the receiver takes
  the runnext slot (`crates/cheby_runtime/src/fiber_ops/channel.rs`). With 801 stages, idle
  workers steal runnable stages, so different parts of the pipeline run at the same time. The
  whole run used 140 ms of user CPU in 31 ms of wall time, and Go shows the same pattern (183 ms).
  In a scratch run at a larger `n`, `CHEBY_THREADS=1` was several times slower than the default
  eight workers. The BEAM rows follow the SPEC's pull protocol. It keeps one message in flight in
  the whole pipeline, so their stages cannot overlap.
- **The per-message costs from ping_pong apply here too, and they come from the current
  implementation.** Each receive allocates an `Ok(value)` cell, since `channel::receive` returns a
  `Result` (D-054). Each send grows a heap worklist to mark a plain integer shared (D-705,
  `crates/cheby_runtime/src/rc.rs`). In a profile at a larger `n`, the stack switch comes first,
  then the channel kernels and these allocations.
- **Shutdown is cheap because the stages are detached.** The program starts every stage with
  `fiber::spawn_detached` and returns from `main`, and the runtime kills the remaining fibers at
  exit (D-073). The tail's receiver is dropped when `primes` returns, so the last filters can end
  on their own. Nothing waits for the pipeline to drain.
- **Peak memory grows with the number of fibers.** Cheby peaks at 35.0 MB, against 21.3 MB for
  ping_pong's two fibers. Go peaks at 6.9 MB and rust-tokio at 3.8 MB. Each of the 802 fibers has
  its own stack slot (8 MiB of address space, D-125), with its control block at the top (D-677),
  and it touches at least one 16 KiB page of that slot on Apple silicon. In scratch runs, peak
  memory grew by about that much for each extra fiber. The BEAM rows peak at 74.5 MB to 76.6 MB.
- **Some rows do slightly different work.** Cheby's run time is an estimate: its bench run minus
  its 11 ms size-0 run, which includes eager JIT of the whole program. Rust-tokio, Python, Nim and
  Ruby use capacity-1 channels, so their stages can run one number ahead and do a few percent
  more filter work. Koka's 53.4 s row is not comparable: its `std/async` has no dynamic spawn, so
  each handoff costs O(pipeline depth).
- **Blocking condition variables slow the C++ row.** C++ takes 1.99 s, 3.71× Rust, and spent
  11.8 s of CPU in the kernel. Its implementation's notes trace this to libc++ on macOS, whose
  condition variable sleeps in the kernel at once. Rust's zero-capacity channel spins briefly
  before it parks.
