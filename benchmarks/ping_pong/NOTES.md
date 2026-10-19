- **Cheby is second of the 19 comparable languages, behind Go.** Its estimated run time is ≈ 71 ms
  [67 ms–72 ms], and the whole process takes 82 ms. Go takes 63 ms, so Cheby needs 1.13× Go's
  time, and the rust-tokio variant takes 51 ms (1.39×). TypeScript takes 101 ms. The BEAM rows take
  215 ms (Erlang) to 234 ms (Elixir), about 3× Cheby. Rust's OS threads take 677 ms, 9.51× Cheby.
- **A handoff stays on one worker thread and never enters the kernel.** A send on a capacity-0
  channel writes the value into the parked receiver's wait node. It then puts that fiber in its
  worker's runnext slot (`crates/cheby_runtime/src/fiber_ops/channel.rs`, `wake` in
  `crates/cheby_runtime/src/sched/mod.rs`, D-689). The sender parks next, and the receiver runs on
  the same thread. So the whole run used 89 ms of user CPU in 82 ms of wall time, and only 8.3 ms
  of system time.
- **Each message still makes two heap allocations, which is the current implementation.**
  `channel::receive` returns a `Result` (D-054, language design). The runtime allocates a new
  `Ok(value)` cell for every value received (`values::ok` in `channel.rs`). `CHEBY_RT_STATS=1`
  counts exactly two allocations per round, one `Ok` cell for each of its two receives.
  `channel::send` marks the value shared (D-705). `rc::mark_shared` grows a worklist on the Rust
  heap before it looks at the value, even when the value is a plain integer
  (`crates/cheby_runtime/src/rc.rs`). That counter leaves this buffer out, since it is not an
  object (`alloc/scratch.rs`). The SPEC expects that "a message allocates nothing", but that does
  not hold today. A profile at a larger `n` puts the stack switch first, with these allocations
  and the channel kernels after it. The language does not require either allocation.
- **Read the start-up column before you compare rows.** Cheby's run time is its bench run minus
  its 11 ms size-0 run, so it is an estimate. Every other row includes its start-up. The SPEC asks
  for bench minus size 0 for every language. That changes little for Go (1.7 ms start-up). It
  changes more for TypeScript (25 ms) and the BEAM (Erlang starts in 90 ms), whose message loops
  are closer to Cheby's than their totals suggest. Rust-tokio uses capacity 1, since tokio's mpsc
  has no capacity 0. Koka's row is single-threaded and not comparable.
- **Peak memory is the runtime's floor, not the messages.** Cheby peaks at 21.3 MB, close to its
  hello_world (18.9 MB). Go peaks at 4.3 MB, Rust at 1.8 MB and the BEAM rows at 71 MB to 72 MB.
  The program has 49 lines, against 32 for Go and 24 for Erlang.
- **The kernel sets the time of the OS-thread rows.** The compiled ones, Rust, Odin, Zig, Nim and
  C++, take 677 ms to 800 ms, and system time is most of each run: 574 ms for Rust and 712 ms for
  C++. OCaml's systhreads (1.45 s) and Ruby's threads (1.79 s) are slower still. Every message
  wakes a sleeping OS thread through the kernel. The fastest task runtimes avoid that: Cheby spent
  8.3 ms in the kernel, TypeScript 5.9 ms, Go 21 ms and rust-tokio 34 ms. Not every task runtime
  does. Swift's main-actor executor spent 3.22 s in the kernel, C# 1.25 s, core.async 1.17 s,
  OCaml Eio 627 ms and Python's asyncio 602 ms.
