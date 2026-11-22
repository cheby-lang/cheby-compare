- **Cheby has the two fastest rows, but at this size the executable ties with Go.** The executable
  takes 19 ms [19 ms–21 ms] and `cheby run` 26 ms [25 ms–31 ms] as a whole process. Go takes 28 ms
  [19 ms–34 ms]. As the SPEC says, these rows are dominated by start-up and noise, so they should
  not be ranked against each other. The rust-tokio variant takes 34 ms. Every other language is far
  behind. Swift takes 98 ms (5.05× the executable), Java 207 ms (10.7×), the BEAM rows 238 ms to 272
  ms (12.3× to 14.0×), Rust 538 ms (27.8×) and OCaml's systhreads 4.57 s (235×).
- **Capacity-0 channels let the pipeline run on several cores.** Each handoff works as in
  `ping_pong`: the value goes straight into the parked receiver's wait node, and the receiver takes
  the runnext slot (`crates/cheby_runtime/src/fiber_ops/channel.rs`). With 801 stages, idle workers
  steal runnable stages, so different parts of the pipeline run at the same time. The executable
  used 104 ms of user CPU in 19 ms of wall time, and Go shows the same pattern (183 ms). With
  `CHEBY_THREADS=1` the same executable took 57 ms, three times as long. At `n = 3000` it took 845
  ms against 177 ms. The BEAM rows follow the SPEC's pull protocol. It keeps one message in flight
  in the whole pipeline, so their stages cannot overlap.
- **The per-message cost from `ping_pong` applies here too, and it comes from the current
  implementation.** Each receive allocates an `Ok(value)` cell, since `channel::receive` returns a
  `Result` (D-054). A send of a plain integer allocates nothing (D-705,
  `crates/cheby_runtime/src/rc.rs`). The run makes 467,294 allocations. Cheby's own `fiber/sieve`
  benchmark, which runs long enough to profile, spends 40% of its samples in the stack switch
  (`docs/perf/optimization-log.md` in the Cheby repository).
- **Shutdown is cheap because the stages are detached.** The program starts every stage with
  `fiber::spawn_detached` and returns from `main`, and the runtime kills the remaining fibers at
  exit (D-073). The tail's receiver is dropped when `primes` returns, so the last filters can end on
  their own. Nothing waits for the pipeline to drain.
- **Peak memory grows with the number of fibers.** The executable peaks at 18.1 MB, against 3.9 MB
  for `ping_pong`'s two fibers. That is about 18 KiB for each of the 800 extra fibers. Each fiber
  has its own stack slot (8 MiB of address space, D-125), with its control block at the top (D-677),
  and it touches at least one 16 KiB page of that slot on Apple silicon. `cheby run` peaks at 33.3
  MB. Go peaks at 6.9 MB and rust-tokio at 3.8 MB. The BEAM rows peak at 74.5 MB to 76.6 MB.
- **Some rows do slightly different work.** Rust-tokio, Python, Nim and Ruby use capacity-1
  channels, so their stages can run one number ahead and do a few percent more filter work. Koka's
  53.4 s row is not comparable: its `std/async` has no dynamic spawn, so each handoff costs
  O(pipeline depth).
- **Blocking condition variables slow the C++ row.** C++ takes 1.99 s, 3.71× Rust, and spent 11.8 s
  of CPU in the kernel. Its implementation's notes trace this to libc++ on macOS, whose condition
  variable sleeps in the kernel at once. Rust's zero-capacity channel spins briefly before it parks.
