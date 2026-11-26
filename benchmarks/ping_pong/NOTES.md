- **Cheby's executable is second of the 23 comparable rows, at 57 ms.** Its ten timings span 55 ms
  to 58 ms. Only the rust-tokio variant (51 ms) is faster. Go takes 63 ms and `cheby run` 64 ms as a
  whole process, which includes 8.8 ms of start-up. TypeScript takes 101 ms. The BEAM rows take 215
  ms (Erlang) to 234 ms (Elixir), about 4× the executable. Rust's OS threads take 677 ms, 11.9× the
  executable.
- **A handoff stays on one worker thread and never enters the kernel.** A send on a capacity-0
  channel writes the value into the parked receiver's wait node. It then puts that fiber in its
  worker's runnext slot (`crates/cheby_runtime/src/fiber_ops/channel.rs`, `wake` in
  `crates/cheby_runtime/src/sched/mod.rs`, D-689). The sender parks next, and the receiver runs on
  the same thread. So the executable used 56 ms of user CPU in 57 ms of wall time, and only 1 ms of
  system time.
- **Each message still makes one heap allocation, which is the current implementation.**
  `channel::receive` returns a `Result` (D-054, language design). The runtime allocates a new
  `Ok(value)` cell for every value received (`values::ok` in `channel.rs`). `CHEBY_RT_STATS=1`
  counts exactly two allocations per round, one `Ok` cell for each of its two receives. The SPEC
  expects that "a message allocates nothing", but that does not hold today. The language does not
  require the allocation. A send allocates nothing now: `channel::send` marks the value shared
  (D-705), and `rc::mark_shared` returns at once for a plain integer, where in October it grew a
  worklist first.
- **The stack switch is the largest cost left.** Cheby's own `fiber/ping_pong` benchmark, which runs
  long enough to profile, spends most of its time in the return after the stack switch
  (`docs/perf/optimization-log.md` in the Cheby repository). This run is too short to profile.
- **Read the start-up column before you compare rows.** Every row's run time includes its start-up.
  That changes little for Cheby's executable (1.8 ms) and Go (1.7 ms). It changes more for
  TypeScript (25 ms) and the BEAM (Erlang starts in 90 ms), whose message loops are closer to
  Cheby's than their totals suggest. Rust-tokio uses channels of capacity 1, since tokio's mpsc has
  none of capacity 0. Koka's row is single-threaded and not comparable.
- **The executable peaks at 3.9 MB.** Go peaks at 4.3 MB, rust-tokio at 2.3 MB, Rust at 1.8 MB and
  the BEAM rows at 71 MB to 72 MB. `cheby run` peaks at 18.9 MB, close to the 16.4 MB floor of any
  `cheby run` process (`hello_world`). The program has 39 lines, against 32 for Go and 24 for
  Erlang.
- **The kernel sets the time of the OS-thread rows.** The compiled ones, Rust, Odin, Zig, Nim and
  C++, take 677 ms to 800 ms, and system time is most of each run: 574 ms for Rust and 712 ms for
  C++. OCaml's systhreads (1.45 s) and Ruby's threads (1.79 s) are slower still. Every message wakes
  a sleeping OS thread through the kernel. The fastest task runtimes avoid that: Cheby's executable
  spent 1 ms in the kernel, TypeScript 5.9 ms, Go 21 ms and rust-tokio 34 ms. Not every task runtime
  does. Swift's main-actor executor spent 3.22 s in the kernel, C# 1.25 s, core.async 1.17 s, OCaml
  Eio 627 ms and Python's asyncio 602 ms.
