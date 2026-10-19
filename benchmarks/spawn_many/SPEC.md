# spawn_many

Spawn many short tasks in batches, join each batch, and print the sum of the results.

## Purpose

It stresses the cost of creating, scheduling and joining a task. Each task does a little pure
integer work, ten generator steps, so the time goes mostly to spawn and join, not to the work.
The work is kept this small on purpose: with more of it, interpreters and runtimes limited to one
thread would be measured on their arithmetic, and M:N runtimes would also win by spreading that
arithmetic over every core. Cheby's own `bench/runtime/fiber/spawn_join` uses a single step per
fiber for the same reason.

- Tasks are spawned in batches of 1,000: a batch is spawned, then fully joined, then the next batch
  starts. This keeps languages whose primitive is an OS thread feasible: never more than 1,000
  threads exist at once. It mirrors Cheby's own `bench/runtime/fiber/spawn_join`.
- Languages with lightweight tasks (BEAM processes, goroutines, virtual threads, tokio tasks, Eio
  fibers) should beat languages whose primitive is an OS thread (Rust's `std::thread`, C++, Zig,
  Odin, Nim, Ruby) by an order of magnitude. Interpreters pay for the work loop itself too, but at
  ten steps per task it is a minor part of their time.
- This is expected to be a **Cheby strength**. Cheby's fibers are M:N scheduled over the default
  number of worker threads, with cheap stacks and structured scopes (`fiber::scope`). One fiber
  costs about 1 µs in the reference implementation, against about 10 µs for a Rust
  `std::thread`. The probe also checks that scope bookkeeping and `join` stay cheap.

## Arguments

One argument: `n`, the number of tasks, a non-negative integer. `B = 1000` (the batch size) and
`ROUNDS = 10` are fixed constants, not arguments.

## Algorithm

```text
B          = 1000
ROUNDS     = 10
MODULUS    = 2147483647          # 2^31 - 1
MULTIPLIER = 48271               # the MINSTD generator

work(index):                     # runs inside the task, never in the spawner
  x = index + 1
  repeat ROUNDS times:
    x = (x * MULTIPLIER) mod MODULUS
  return x

spawn_and_join(start, count):    # one batch
  spawn one task for each index in start, start+1, ..., start+count-1;
    the task computes work(index) and returns it
  join every task of the batch and add up their results
  return that batch sum

main(n):
  sum = 0
  start = 0
  while start < n:
    sum = sum + spawn_and_join(start, min(B, n - start))
    start = start + B
  print "tasks: {n}"
  print "sum: {sum}"
```

Rules:

- **One task per index.** Each index gets its own task, created with the language's primitive
  from the table below. Never run several indices in one task, never chunk the work by hand, and
  never compute `work` in the spawner.
- **Spawn all, then join all.** All `count` tasks of a batch are spawned before the first join of
  that batch. The next batch starts only after every task of this batch has been joined. Tasks may
  be joined in any order: the sum does not depend on it.
- **Results come back through the join.** A task returns its value to the spawner through the
  primitive's join (a join handle, a future, a promise, a message). Where the join returns nothing
  (Go, Zig, Odin, Nim, C++, OCaml threads), each task writes only its own slot of a per-batch
  result array, and the spawner sums the array after joining. No shared counters, atomics or locks
  on the sum.
- **No pre-started worker pools** written by the program. A pool that the runtime owns and uses
  for every task (the .NET thread pool, Scala's global `ExecutionContext`, Clojure's `future` pool,
  Java's virtual-thread carriers, tokio's workers) is fine, because each index is still its own
  task.
- **Default threads.** Keep the runtime's default thread count. Do not set `GOMAXPROCS`, tokio
  worker counts, `+S` for BEAM, or the like.
- `work` is the loop above, 10 steps, with no shortcut. Do not precompute `MULTIPLIER^10`.

### Integer ranges

`x` is always below 2^31, so `x * MULTIPLIER` is below 2^47. No step wraps, and every language,
including JavaScript numbers, computes it exactly. Use 64-bit integers (`i64`/`u64`, `long`,
`Int64`). The sum stays below 2^53 for every `n` up to 4,194,304, so JavaScript numbers hold it
exactly at every size listed here. `mod` is the plain remainder: every operand is positive.

Check values: `work(0) = 1596680831`, `work(1) = 1045878015`, `work(2) = 495075199`, the sum of
`work(0) … work(999)` is `1073703148184`.

## Output

Exactly two lines, each ending in `\n`. Integers print in plain decimal.

```text
tasks: <n>
sum: <sum>
```

For `n = 2500` (two full batches and one batch of 500):

```text
tasks: 2500
sum: 2686075967465
```

## Size 0

`n = 0` spawns no batch. It still parses the argument and prints both lines.

```text
tasks: 0
sum: 0
```

## Sizes

| Size    | `n`     | Notes                                                                                                    |
| ------- | ------- | -------------------------------------------------------------------------------------------------------- |
| `zero`  | 0       | no batch                                                                                                 |
| `test`  | 2,500   | three batches, the last one partial                                                                      |
| `bench` | 100,000 | 100 batches; Rust about 1.2 s (OS threads); Cheby about 0.11 s in total, about 0.10 s estimated run time |

Cheby's split is an estimate (see CONVENTIONS.md, "Measurement"): its run time is the bench run minus
a size-0 run of the same program, about 12 ms of start-up and eager JIT. At about 0.1 s of run time,
noise in either run is a large relative error, so read Cheby's row here as approximate. `n` stays at
100,000 because a larger `n` pushes Rust's OS threads past 2 s.

## Concurrency primitive per language

Use exactly this primitive. "Batch" means the 1,000 tasks of one `spawn_and_join` call.

| Language            | Spawn                                                                                               | Join                                                 |
| ------------------- | --------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Cheby               | `fiber::spawn(scope, fn() { work(i) })` in a `fiber::scope`                                         | `fiber::join`, then the scope ends                   |
| Rust                | `scope.spawn(move \|\| work(i))` in a `std::thread::scope`                                          | `handle.join()`                                      |
| `rust-tokio`        | `tokio::spawn(async move { work(i) })`, `#[tokio::main]`                                            | `handle.await` on each `JoinHandle`                  |
| Go                  | `go` with a `sync.WaitGroup` per batch                                                              | `wg.Wait()`, then sum the batch's result slice       |
| Zig                 | `std.Thread.spawn`                                                                                  | `thread.join()`, then sum the batch's result array   |
| Odin                | `thread.create_and_start_with_poly_data` (`core:thread`)                                            | `thread.join`, `thread.destroy`, then sum the array  |
| C++                 | `std::jthread` (or `std::thread`) running `results[j] = work(i)`                                    | `join` every thread, then sum the result array       |
| Nim                 | `createThread` (`std/typedthreads`)                                                                 | `joinThread`, then sum the batch's result array      |
| Swift               | `group.addTask { work(i) }` in `withTaskGroup` per batch                                            | `for await` over the group                           |
| Erlang              | `spawn(fun() -> Parent ! {Ref, work(I)} end)`                                                       | `receive {Ref, V}` once per task of the batch        |
| Elixir              | `Task.async(fn -> work(i) end)`                                                                     | `Task.await_many(tasks, :infinity)`                  |
| Gleam               | `process.spawn` (`gleam_erlang`), the task sends to a `Subject`                                     | `process.receive_forever` once per task of the batch |
| Java                | `executor.submit(() -> work(i))`, `Executors.newVirtualThreadPerTaskExecutor()` per batch           | `future.get()`                                       |
| Scala               | `Future(work(i))` on `ExecutionContext.global`                                                      | `Await.result(Future.sequence(batch), Duration.Inf)` |
| Clojure             | `(future (work i))`                                                                                 | `deref` (`@`)                                        |
| `clojure-coreasync` | `(async/go (work i))`                                                                               | `(async/<!! ch)` on each returned channel            |
| C#                  | `Task.Run(() => Work(index))`, `index` a per-iteration local (see below)                            | `await Task.WhenAll(batch)`                          |
| TypeScript          | an `async` task that first does `await Promise.resolve()`                                           | `await Promise.all(batch)`                           |
| Python              | `asyncio.create_task(work(i))`, `work` is `async def`                                               | `await asyncio.gather(*batch)`                       |
| Ruby                | `Thread.new { work(i) }`                                                                            | `thread.value`                                       |
| OCaml               | `Thread.create` (the `threads.posix` library)                                                       | `Thread.join`, then sum the batch's result array     |
| `ocaml-eio`         | `Fiber.fork_promise ~sw` inside one `Switch.run` per batch, a task that first does `Fiber.yield ()` | `Promise.await_exn`                                  |
| Koka                | see below                                                                                           | see below                                            |

## Per-language guidance

- **Result arrays.** Where the join returns nothing, allocate one array (or slice) of `count`
  slots per batch. Task `j` writes slot `j` only. Sum after all joins of the batch.
- **Rust**: `std::thread::scope` per batch; collect the `ScopedJoinHandle`s in a `Vec`, then join
  them in order.
- **Go**: one `sync.WaitGroup` and one `[]int64` per batch; `wg.Go` or `wg.Add`/`Done`.
- **C++**: one `std::jthread` per task, kept in a `std::vector<std::jthread>` per batch, and a
  `std::vector<std::int64_t>` of result slots. The thread vector goes out of scope (or each
  `std::thread` is joined) before the batch is summed, so every OS thread has exited before the
  next batch starts. Do not use `std::async`: Apple's libc++ detaches its thread, and
  `future.get()` returns before the thread exits.
- **Swift**: top-level `await` or an `@main` struct with `static func main() async`. One
  `withTaskGroup(of: Int.self)` per batch.
- **Erlang, Elixir, Gleam**: one process per task. Tag each batch's messages with a fresh `Ref`
  (Erlang) or use a fresh `Subject` per batch (Gleam), so a batch never reads another batch's
  results. Loops are tail-recursive functions.
- **Gleam**: exactly one primitive, from `gleam_erlang`: one `process.new_subject()` per batch,
  `process.spawn` per task, the task sends `work(i)` to that subject, and the spawner calls
  `process.receive_forever` once per task. Do not use `gleam_otp`'s task API, whose presence and
  shape differ between releases. `impl.toml` names `gleam_erlang` under `libs`.
- **C#**: `static async Task Main`. A C# `for` variable is shared by every lambda, so copy the
  index into a local inside the loop (`var index = start + j;`) before `Task.Run(() =>
  Work(index))`, or build the batch with `Enumerable.Range(start, count).Select(i => Task.Run(()
  => Work(i))).ToArray()`.
- **Clojure**: `mapv` (not lazy `map`) to start a batch's futures, so all of them start before the
  first `deref`. Call `(shutdown-agents)` at the end so the JVM exits promptly.
- **Java**: `try (var ex = Executors.newVirtualThreadPerTaskExecutor()) { … }` per batch.
- **TypeScript**: Node is single-threaded, so a task is a promise. `async function task(i) { await
  Promise.resolve(); return work(i); }`: the first `await` makes the work run after the spawn, as
  with Python's `create_task`, instead of inside the spawning call.
- **ocaml-eio**: Eio runs a forked fiber at once, inside `Fiber.fork_promise`, until it blocks.
  So each task first does `Fiber.yield ()` and then returns `work(i)`. The yield queues the task
  and returns to the spawner, so the work runs after the spawn and a batch holds all its tasks
  suspended, as with TypeScript's `await Promise.resolve()`.
- **Python**: `work` is an `async def` with no `await` inside; one `asyncio.run(main())`.
- **OCaml**: Domains are not a fit (the runtime recommends at most about 128 at once). Use
  `Thread` from the compiler's own `threads.posix` library. The domain lock makes the work run one
  thread at a time, which is the language's normal behaviour for systhreads.
- **Koka**: Koka 3 has no thread or task library in its standard install. Write a small
  cooperative scheduler with an effect handler in the program: `spawn` adds a suspended task to a
  queue and returns a handle, `join` runs queued tasks until that handle's result is ready. Say so
  in `impl.toml` under `notes`. That scheduler is written by the program, not a runtime primitive,
  so Koka's row is not comparable to the others: the benchmark's `NOTES.md` footnotes it in the
  report.
- **Cheby**: one `fiber::scope` per batch; spawn into it with a local recursive function that
  builds a list of `Fiber`s, then `list::fold` over the list with `fiber::join`. The batch loop is
  a local recursive function in `main`.
