- **Cheby is fifth of the 19 comparable languages, in the lightweight-task band.** Its estimated
  run time is ≈ 88 ms [87 ms–89 ms], and the whole process takes 99 ms. Go (16 ms, so Cheby is
  5.39× slower), Swift (59 ms), TypeScript (62 ms) and C# (72 ms) are ahead. So are the rust-tokio
  (29 ms) and OCaml Eio (62 ms) variants. Java's virtual threads come right behind at 96 ms.
  Erlang takes 157 ms (1.78× Cheby), Gleam 197 ms and Elixir 342 ms. Rust's OS threads take
  805 ms, 9.13× Cheby.
- **Each task does only ten generator steps, so the rows measure spawn and join.** A Cheby spawn
  allocates the closure and a `Fiber` handle with its join cell, and marks the closure shared
  (D-705). It also takes a stack slot (8 MiB of address space, D-125, with free slots reused warm,
  D-677), builds a control block, and records the fiber in its scope under the scope's lock
  (`crates/cheby_runtime/src/fiber_ops/spawn.rs`). The new fiber takes the runnext slot. The fiber
  it displaces goes to the worker's deque, and an idle worker is woken through a condition
  variable (`schedule` and `notify_parked` in `crates/cheby_runtime/src/sched/mod.rs`). Each
  fiber takes the scope's lock again when it ends. The locking, the condition-variable wake-ups
  and the separate handle and join-cell allocations are the current implementation. Registering
  each fiber with its scope (structured concurrency, D-040) and giving each fiber its own stack
  (D-125) are design choices.
- **Waking workers and sharing the scope's lock show up in the profile.** In a profile at a larger
  `n`, the spawn path is the largest item. Time also goes to the scope lock's slow path, where the
  spawner and the ending fibers meet, and to condition-variable waits and signals. The whole run
  spent 53 ms in the kernel, against 9.4 ms for Go.
- **The program's `[fiber, ..fibers]` is not a cheap cons, which is the current implementation.**
  `List` is an RRB-tree vector, not a linked list (D-039, language design). The compiler lowers
  `[x, ..xs]` to a one-element list concatenated with `xs`
  (`crates/cheby_mir/src/lower/list.rs`), which allocates new tree nodes for every task.
  `CHEBY_RT_STATS=1` counts about four more allocations per task than with
  `list::prepend(fibers, x)` or `[..fibers, x]`, which update the list in place. A scratch copy
  that used `[..fibers, x]` ran clearly faster at a larger `n`. The program keeps the cons form,
  the idiom of the other functional rows. The compiler could lower it to the in-place `prepend`
  kernel.
- **With one worker thread, the stack pool hits a cliff, but this run avoids it.** A stack class
  keeps at most 64 warm free slots (`FREE_KEEP` in `crates/cheby_runtime/src/fiber/stack.rs`),
  and a batch holds up to 1,000 live fibers. With `CHEBY_THREADS=1`, most slots are released whole
  and fault in again, which makes the run several times slower. With the default eight workers
  almost every slot is reused warm. Cheby's `bench/runtime/README.md` documents this.
- **Read Cheby's row as approximate.** Its run time is the bench run minus its 11 ms size-0 run
  (start-up and eager JIT), which assumes that both cost the same inside the bench run.
  Run-to-run spread was small: the whole process took 97 ms to 100 ms over ten runs. The
  implementation's notes record that it slows down far more than Go or rust-tokio when the CPU is
  oversubscribed. Koka's row (14 ms) is not comparable. Koka's standard `std/async` has no dynamic
  spawn (`interleaved` takes a fixed list of strands and returns no handle), so its program
  carries its own single-threaded cooperative scheduler, an effect handler with a queue. The row
  measures that scheduler, not a runtime's task primitive.
- **The compiled OS-thread rows peak near 17.6 MB.** Rust, Zig, Odin, C++ and Nim run up to 1,000
  threads per batch and peak at 17.5 MB to 17.9 MB, against 11.7 MB for Go and 24.3 MB for
  Cheby. Their time is mostly kernel time: Rust's 805 ms run spent 1.77 s of CPU in the kernel.
  OCaml's systhreads peak at 81.2 MB and Ruby's threads at 151 MB.
