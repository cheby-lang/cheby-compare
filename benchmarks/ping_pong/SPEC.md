# ping_pong

Two lightweight tasks pass a number back and forth `n` times over two channels. Task A sends
`i` on `ping`, task B answers `i + 1` on `pong`, and A adds up the answers. The program prints `n`
and the sum.

## Purpose

- **What it stresses.** The cost of one blocking handoff between two tasks. Each round is two
  messages, and each message wakes the other task, so a run does `2n` task switches and almost
  no other work. Nothing is allocated per message beyond what the channel itself needs.
- **Where languages differ.** Runtimes with green threads (goroutines, BEAM processes, virtual
  threads, async tasks, Cheby fibers) switch tasks in user space. Languages whose standard
  primitive is an OS thread pay a kernel wake-up and a context switch per message, which is
  several times slower. Interpreters add their dispatch cost to every switch. CPython's asyncio
  also pays one event-loop iteration per switch, and each iteration polls the selector with a
  system call (`kevent` on macOS). That cost depends on the OS scheduler more than on the
  interpreter, so the Python number swings with machine load: measure it only on a quiet machine,
  and treat it as the least stable row.
- **Expected for Cheby: in the green-thread group.** Cheby schedules fibers M:N, and a send on a
  capacity-0 channel hands the value straight to the waiting receiver (§10.5, `std::channel`). A
  switch stays inside the runtime. The integers are unboxed, so a message allocates nothing. The
  comparison with goroutines and the BEAM is the interesting one, and Go is the bar: in a
  calibration run Go was a little faster than Cheby (see Sizes).

## Arguments

One argument: `n`, a non-negative decimal integer, the number of rounds.

## Algorithm

```text
echo(n, ping, pong):                 # task B
  repeat n times:
    x = receive(ping)
    send(pong, x + 1)

play(n, ping, pong):                 # task A
  sum = 0
  for i in 1 .. n:                   # inclusive, in increasing order
    send(ping, i)
    sum = sum + receive(pong)
  return sum

main(n):
  ping = new channel of integers, capacity 0
  pong = new channel of integers, capacity 0
  b = spawn task B: echo(n, ping, pong)
  sum = play(n, ping, pong)          # A: the main task itself, or a spawned task (below)
  join b
  print n
  print sum
```

What must be the same everywhere:

- **Two tasks of the same kind, two channels.** A and B must be the same kind of task, so that
  every handoff is a switch between two lightweight tasks of the runtime, never between a
  lightweight task and an OS thread.
  - Where the program's entry point already runs as one of the runtime's tasks, A is that main
    task: Cheby's main fiber, Go's main goroutine, the BEAM process that runs `main`, the main
    coroutine under `asyncio.run`, the main async function in TypeScript and C#, Swift's async
    main, Koka's `interleaved` strand, Eio's main fiber. Where the primitive is an OS thread (Rust
    std, Zig, Odin, C++, OCaml, Nim, Ruby), A is the main thread, which is an OS thread like B.
  - Where the entry point is not a lightweight task (the JVM main thread with virtual threads,
    the future that `#[tokio::main]` runs through `block_on` on the main thread, the Clojure main
    thread with core.async), main starts A as a lightweight task of the same kind as B
    (`Thread.ofVirtual().start`, `tokio::spawn`, a `go` block). Main then joins A, taking the sum
    from it, and then joins B. Main does no other work while A runs.

  Task B is spawned exactly once, before the first message. `ping` carries values from A to B
  only, `pong` from B to A only.

- **One value per message.** Every `send` carries one integer and every `receive` takes one. No
  batching, no shared counter, no shared memory instead of the channel. On the BEAM a message is a
  small tuple such as `{ping, I}` or `{pong, X}`, and B learns A's pid (or subject) once, before
  the first round.
- **Rendezvous where possible.** Use capacity 0 where the primitive has it. Use capacity 1 where
  it has no 0 (Python `asyncio.Queue`, Ruby `SizedQueue`, tokio `mpsc`). Use the unbounded mailbox
  or stream where the idiomatic primitive has no bounded form (BEAM mailboxes, Swift
  `AsyncStream`, Koka `std/async` channels, whose `emit` never blocks). The protocol never has
  more than one message in flight, so the three behave the same.
- **B knows `n`.** B does exactly `n` rounds and then returns. Do not end B by closing a channel,
  by a sentinel value or by a timeout. Closing or dropping the channels afterwards, as cleanup, is
  fine.
- **Join.** B's end is awaited through the primitive's own join before printing: thread `join`,
  awaiting the task or future, the end of a Cheby `fiber::scope`, a Go `sync.WaitGroup`, Koka's
  `interleaved` (which returns when both strands end), B's result channel in core.async. On the
  BEAM B ends right after its last reply, and A does not wait further.
- **No select, no polling, no sleeping, no spinning.** `send` and `receive` block (or `await`) the
  task until the other side is ready.
- **Integers.** Use 64-bit signed integers (or the language's default integer if it is at least
  that wide, or arbitrary precision on the BEAM, Python and Ruby). The sum is `n * (n + 3) / 2`,
  well below `2^53`, so TypeScript's `number` is exact. Do not print the closed form: the sum must
  come from the received values.
- **Default runtime settings.** Keep the default thread count, scheduler count and pool size of
  every runtime. Do not pin threads or set `GOMAXPROCS`, `+S` or `--threads`.

## Idiomatic primitive per language

Standard library only, except the library rows (`gleam_erlang`, tokio, core.async, Eio). Name a
library in `impl.toml` under `libs`.

| Id                  | Tasks                                                                              | Channels                                                                           |
| ------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `cheby`             | `fiber::scope` and `fiber::spawn`                                                  | `channel::new::<Int>(0)`, `channel::send`, `channel::receive`                      |
| `gleam`             | `process.spawn` (gleam_erlang)                                                     | `Subject`s: `process.new_subject`, `process.send`, `process.receive_forever`       |
| `rust`              | `std::thread::spawn`, `join`                                                       | `std::sync::mpsc::sync_channel(0)`                                                 |
| `rust-tokio`        | `#[tokio::main]` (multi-thread runtime), `tokio::spawn` for A and B, both awaited  | `tokio::sync::mpsc::channel(1)`                                                    |
| `go`                | goroutine, `sync.WaitGroup`                                                        | unbuffered `make(chan int64)`                                                      |
| `zig`               | `std.Io.Threaded` (default), `io.concurrent` and `Future.await` (or an `Io.Group`) | `std.Io.Queue(i64)` with a zero-length buffer, `putOne` and `getOne`               |
| `odin`              | `core:thread`                                                                      | `core:sync/chan`, unbuffered (or a one-slot channel from `core:sync`)              |
| `cpp`               | `std::thread`, `join`                                                              | a one-slot channel built from `std::mutex` and `std::condition_variable`           |
| `erlang`            | `spawn`                                                                            | `Pid ! Msg` and `receive`                                                          |
| `python`            | `asyncio.run`, `asyncio.create_task`, `await`                                      | `asyncio.Queue(maxsize=1)`                                                         |
| `java`              | virtual threads for A and B: `Thread.ofVirtual().start`, `join`                    | `java.util.concurrent.SynchronousQueue<Long>`, `put` and `take`                    |
| `typescript`        | async functions, the B promise awaited at the end                                  | a hand-written rendezvous channel on promises (below)                              |
| `swift`             | `Task { }` from the async main (main actor), `await task.value`                    | `AsyncStream.makeStream(of: Int.self)`, one per direction                          |
| `csharp`            | `Task.Run`, `await`                                                                | `Channel.CreateBounded<long>(0)`, `WriteAsync` and `ReadAsync`                     |
| `elixir`            | `spawn`                                                                            | `send` and `receive`                                                               |
| `scala`             | virtual threads for A and B: `Thread.ofVirtual().start`, `join`                    | `java.util.concurrent.SynchronousQueue[Long]`                                      |
| `clojure`           | virtual threads for A and B: `Thread/ofVirtual`, `.join`                           | `java.util.concurrent.SynchronousQueue`, `.put` and `.take`                        |
| `clojure-coreasync` | `go` blocks for A and B, their result channels taken on the main thread with `<!!` | unbuffered `(chan)`, `>!` and `<!` inside the `go` blocks                          |
| `koka`              | `std/async`: `async` and `interleaved(a, b)`, the join is implicit                 | `std/async` `channel()`, `emit` and `receive`                                      |
| `ocaml`             | `Thread.create`, `Thread.join` (threads library)                                   | `Event.new_channel`, `Event.sync (Event.send c v)`, `Event.sync (Event.receive c)` |
| `ocaml-eio`         | `Eio_main.run`, `Eio.Fiber.both` (or `fork` in a switch)                           | `Eio.Stream.create 0`, `Eio.Stream.add` and `Eio.Stream.take`                      |
| `nim`               | `createThread`, `joinThread` (`--threads:on`, the default)                         | `Channel[int]` opened with `open(ch, maxItems = 1)`, `send` and `recv`             |
| `ruby`              | `Thread.new`, `join`                                                               | `SizedQueue.new(1)`, `push` and `pop`                                              |

Notes on the rows:

- **Gleam.** A subject can only be received by the process that created it, so the program uses
  a setup subject. A creates `setup: Subject(Subject(Int))` and `pong: Subject(Int)` and spawns
  B. B creates `ping: Subject(Int)` and sends it on `setup`. A receives it once, before round 1,
  and then uses only `ping` and `pong`. Do not wrap the round messages in a variant, and do not
  use `actor.call` or `process.call`, which create a new reply subject for every message.
- **Erlang, Elixir.** Plain `spawn`, `!`/`send` and `receive`. No `gen_server:call`, which adds a
  monitor and a reference per message. Match the message with a pattern; a selective receive on a
  tag is fine.
- **Java, Scala, Clojure.** The JVM main thread is a platform thread, so it must not be A: a
  handoff between it and a virtual thread parks and unparks an OS thread on every message. Main
  starts B and then A as virtual threads, joins A and reads the sum it produced (for example
  from a field or an `AtomicLong` written once at A's end, or through a `FutureTask` run on the
  virtual thread), then joins B.
- **rust-tokio.** `#[tokio::main]` runs its future through `block_on` on the main OS thread, not
  on a worker. Main spawns B and then A with `tokio::spawn`, awaits A's `JoinHandle` for the sum,
  then awaits B's.
- **clojure-coreasync.** A and B are both `go` blocks and use the parking `>!` and `<!`. Main
  waits for A's result channel and then B's with the blocking `<!!`, once each. Do not run A on
  the main thread with `>!!` and `<!!`, which park an OS thread on every message.
- **Zig.** Create the `std.Io.Threaded` instance the way the standard library documents it and
  keep its default limits. Start B with `io.concurrent` (not `io.async`, which may run B to
  completion before A starts and deadlock) and await its future after A's loop. A is the main
  thread. A `std.Io.Queue(i64)` initialised with an empty buffer is a rendezvous: `putOne` waits
  until a getter takes the value.
- **One-slot channel** (C++, Odin without `core:sync/chan`). One mutex, one or two condition
  variables, and an optional value slot. `send` waits while the slot is full, fills it and
  signals. `receive` waits while the slot is empty, takes the value and signals. Use `wait` in a
  loop on the condition, never a spin or a sleep.
- **OCaml.** `Event` channels are synchronous, so they rendezvous like capacity 0. Use systhreads
  (`Thread`), the standard tool for blocking concurrency, not `Domain.spawn`, which is meant for
  parallelism.
- **Koka.** `interleaved({ play(...) }, { echo(...) })` inside `async` runs A and B as strands
  of the same kind and returns when both end. `std/async` ships with the installed Koka, so it
  counts as the standard library; say so in `impl.toml`'s notes.
- **TypeScript.** Write a small `Channel<T>` class with `send(v: T): Promise<void>` and
  `receive(): Promise<T>`. Keep a queue of waiting receivers (their `resolve` functions) and a
  queue of waiting senders (the value and its `resolve`). `send` hands the value to a waiting
  receiver if there is one, or else waits; `receive` does the opposite. Use only promises: no
  `setTimeout`, `setImmediate` or `queueMicrotask` loops.
- **Swift.** Use an async `@main` (or top-level code). B is created with `Task { }` from it,
  inherits the main actor and stays there, so A and B run cooperatively on the main actor. Do not
  use `Task.detached`, which would put B on the global pool and make every message cross
  executors. `AsyncStream` never blocks a sender, which the protocol makes harmless. A
  hand-written actor channel is also acceptable if that is how you would write it. Say which
  channel and executor you used in `impl.toml`.
- **C#.** `BoundedChannelOptions(0)` (a true rendezvous since .NET 10) with `SingleReader = true`
  and `SingleWriter = true` is fine, since both hold. Keep `FullMode = Wait`. A is the async
  `Main`: it has no synchronization context, so after its first `await` it runs on the thread pool
  like B.

## Output

Two lines, each a decimal integer, with a final newline:

```text
<n>
<sum>
```

For example, with `n = 10`:

```text
10
65
```

## Size 0

`n = 0` creates both channels, spawns B (and A, where main spawns it) and joins it. No message is
sent. The program prints `0` twice. It must take the same path as any other size: no special
case for 0.

## Sizes

| Size    | `n`    | Output (second line) | Rust, Apple M-series |
| ------- | ------ | -------------------- | -------------------- |
| `zero`  | 0      | 0                    | ~3 ms                |
| `test`  | 1000   | 501500               | ~5 ms                |
| `bench` | 300000 | 45000450000          | ~0.7 s               |

The exact outputs are in `expected/`. The bench size follows the convention: Rust's reference
uses OS threads (about 2.3 µs a round). Green-thread runtimes finish it in tens of milliseconds,
so at `bench` their total time is often dominated by start-up (BEAM boot, JVM start). For this
benchmark the comparison that matters is the bench time minus the size-0 time, **for every
language**, not only for Cheby. The report should show it next to the total.

Calibration on one machine, total wall time per run (hyperfine medians, approximate):

| Program                                        | `zero` | `bench` | `bench` minus `zero`                   |
| ---------------------------------------------- | ------ | ------- | -------------------------------------- |
| Go goroutines (scratch build, not in the repo) | ~2 ms  | ~60 ms  | ~58 ms (~0.19 µs a round)              |
| Cheby fibers                                   | ~12 ms | ~80 ms  | ~70 ms (~0.23 µs a round), an estimate |
| Rust threads                                   | ~3 ms  | ~0.7 s  | ~0.7 s (~2.3 µs a round)               |

Cheby's `zero` time is its JIT compile of the whole program plus start-up, so its bench-minus-zero
figure is an estimate of run time (see CONVENTIONS.md). On a loaded machine, Cheby's bench total
ranged from about 0.08 s to 0.18 s. CPython with asyncio takes several seconds, and its time
varies by several times with machine load (see Purpose).
