- **Cheby's executable is seventh of the 23 comparable rows, at 76 ms.** Its ten timings span 75 ms
  to 76 ms, and `cheby run` takes 84 ms as a whole process. Go (16 ms, 4.62× faster), Swift (59 ms),
  TypeScript (62 ms) and C# (72 ms) are ahead. So are the rust-tokio (29 ms) and OCaml Eio (62 ms)
  variants. Java's virtual threads come right behind at 96 ms. Erlang takes 157 ms (2.07× the
  executable), Gleam 197 ms and Elixir 342 ms. Rust's OS threads take 805 ms, 10.6× the executable.
- **Each task does only ten generator steps, so the rows measure spawn and join.** A Cheby spawn
  allocates the closure and a `Fiber` handle with its join cell, and marks the closure shared
  (D-705). It also takes a stack slot (8 MiB of address space, D-125, with free slots reused warm,
  D-677), builds a control block, and records the fiber in its scope under the scope's lock
  (`crates/cheby_runtime/src/fiber_ops/scope.rs`). The new fiber takes the runnext slot. The fiber
  it displaces goes to the worker's deque, and an idle worker is woken through a condition variable
  (`schedule` and `notify_parked` in `crates/cheby_runtime/src/sched/mod.rs`). Each fiber takes the
  scope's lock again when it ends. The locking, the condition-variable wake-ups and the separate
  handle and join-cell allocations are the current implementation. Registering each fiber with its
  scope (structured concurrency, D-040) and giving each fiber its own stack (D-125) are design
  choices.
- **The program's `[fiber, ..fibers]` costs a third of the run, which is the current
  implementation.** `List` is an RRB-tree vector, not a linked list (D-039, language design). The
  compiler lowers `[x, ..xs]` to a push onto a new list and an append of `xs`, which allocates new
  tree nodes for every task. `CHEBY_RT_STATS=1` counts 7.9 allocations per task. A scratch copy that
  used `[..fibers, x]`, which updates the list in place, made 3.0 per task and ran in 51 ms against
  77 ms. The program keeps the cons form, the idiom of the other functional rows. The compiler could
  lower it to the runtime's in-place prepend. Cheby's `docs/perf/optimization-log.md` lists that
  change as a proposal that needs a decision.
- **The run spends 37 ms in the kernel, against 9 ms for Go.** In October's profile at a larger `n`,
  the spawn path was the largest item, followed by the slow path of the scope's lock, where the
  spawner and the ending fibers meet, and by condition-variable waits and signals. This run is too
  short to profile, and that profile has not been repeated.
- **With one worker thread, the stack pool hits a cliff, but this run avoids it.** A stack class
  keeps at most 64 warm free slots (`FREE_KEEP` in `crates/cheby_runtime/src/fiber/stack.rs`), and a
  batch holds up to 1,000 live fibers. With `CHEBY_THREADS=1`, most slots are released whole and
  fault in again: the same executable took 608 ms, 495 ms of it in the kernel. With the default
  eight workers almost every slot is reused warm. Cheby's `bench/runtime/README.md` documents this.
- **Koka's row is not comparable.** Koka's standard `std/async` has no dynamic spawn (`interleaved`
  takes a fixed list of strands and returns no handle), so its program carries its own
  single-threaded cooperative scheduler, an effect handler with a queue. The row (14 ms) measures
  that scheduler, not a runtime's task primitive. The Cheby implementation's notes record that it
  slows down far more than Go or rust-tokio when the CPU is oversubscribed.
- **The compiled OS-thread rows peak near 17.6 MB.** Rust, Zig, Odin, C++ and Nim run up to 1,000
  threads per batch and peak at 17.5 MB to 17.9 MB, against 11.7 MB for Go, 7.3 MB for Cheby's
  executable and 22.6 MB for `cheby run`. Their time is mostly kernel time: Rust's 805 ms run spent
  1.77 s of CPU in the kernel. OCaml's systhreads peak at 81.2 MB and Ruby's threads at 151 MB.
