# prime_sieve

The classic concurrent prime sieve (Hoare's CSP sieve, the Go tour's `sieve.go`). A generator
task emits 2, 3, 4 and so on. Each prime that comes out of the pipeline adds a filter task to its
end, connected by a new channel. After `n` primes the program prints `n`, the `n`-th prime and the
sum of the first `n` primes.

## Purpose

- **What it stresses.** Many blocking handoffs along a long chain of tasks. A number `m` passes
  through the filters one by one until a prime divides it, so primes walk the whole chain. At
  `n = 800` the pipeline grows to 801 tasks and makes about 333,000 handoffs in all, 6,132 of
  them out of the generator. Each handoff wakes the next task. There is almost no other work:
  one `%` per number a filter receives (332,216 at `bench`).
- **Where languages differ.** As in `ping_pong`, but with hundreds of tasks alive at once.
  Runtimes with green threads (goroutines, BEAM processes, virtual threads, async tasks, Cheby
  fibers) switch in user space. Languages whose standard primitive is an OS thread pay a kernel
  wake-up per handoff and keep `n + 2` threads alive (main, the generator and `n` filters),
  which also limits `n`. Interpreters add their dispatch cost to every switch.
- **Green threads are not all in the same band.** Probes at `bench` on a loaded M-series machine:
  Cheby about 0.035 s in all and Go about 0.025 s, both dominated by start-up. Java's virtual
  threads with `SynchronousQueue` took about 0.28 s (0.06 s of it start-up), and Erlang with the
  pull protocol 0.29 to 0.38 s (0.2 s of it start-up). Only the Cheby and Go rows land in the
  start-up-dominated band; see "Reading the Cheby and Go rows" below.
- **Expected for Cheby: a strength.** Cheby schedules fibers M:N, a fiber is cheap to spawn, and
  a send on a capacity-0 channel hands the value straight to the waiting receiver. Integers are
  unboxed, so a handoff allocates nothing. Rust's reference, with OS threads, is about 30 to 40
  times slower per handoff. The comparison with Go is the interesting one, but at this size it
  is decided by start-up and noise, not by the runtimes.

## Arguments

One argument: `n`, a non-negative decimal integer, the number of primes to find.

## Algorithm

```text
generate(out):                       # the generator task
  i = 2
  loop forever:
    send(out, i)                     # blocks until the next stage takes it
    i = i + 1

filter(in, out, prime):              # one filter task per prime
  loop forever:
    m = receive(in)
    if m % prime != 0:
      send(out, m)

main(n):
  ch = new channel of integers
  spawn generate(ch)                 # always, also when n = 0
  last = 0
  sum = 0
  repeat n times:
    prime = receive(ch)
    last = prime
    sum = sum + prime
    next = new channel of integers
    spawn filter(ch, next, prime)    # also after the n-th prime
    ch = next
  shut down (below)
  print "primes: {n}"
  print "last: {last}"
  print "sum: {sum}"
```

What must be the same everywhere:

- **One task per stage.** One generator task and exactly `n` filter tasks, each spawned once, in
  this order. Every filter is spawned right after its prime is received, the `n`-th one included.
  The main task (the main thread, or the coroutine or fiber the runtime starts) receives the
  primes and is not a filter.
- **One new channel per filter.** Each stage talks only to its neighbours. No shared list of
  primes, no shared counter, no trial division outside the filters, no wheel and no skipping of
  even numbers. The generator emits every integer from 2 upward.
- **One value per message.** Every send carries one integer, and every receive takes one. No
  batching.
- **Bounded, blocking channels.** Use capacity 0 (rendezvous) where the primitive has it, and
  capacity 1 where it has no 0. Never a larger buffer. A hand-written channel (TypeScript,
  Swift, C++, Odin without `core:sync/chan`) can always offer 0, so it is a rendezvous. `send`
  and `receive` block (or `await`) the task until the other side is ready. No select, no
  polling, no sleeping, no spinning.
- **Mailbox languages pull** (BEAM, and any primitive whose send never blocks). An unbounded
  mailbox would let the generator run ahead forever, so the downstream stage asks for each
  number. See "Pull protocol" below.
- **Shut down.** After the `n`-th filter is spawned, the program prints and ends without
  waiting for any stage to do more work. Use one of two ways, whichever is natural for the
  primitive:
  1. Print and end the process with the tasks still blocked: Go returning from `main`, Cheby
     returning from `main` with detached fibers (`fiber::spawn_detached`; the program kills them
     when `main` ends, §10.10, D-073), Rust returning from `main` without joining, Zig flushing
     stdout and calling `std.process.exit(0)`, `halt()` on the BEAM, the JVM exiting with only
     virtual (daemon) threads left, detached C++ or Odin threads, `quit(0)` in Nim, `exit 0` in
     OCaml.
  2. Cancel every task at once, then wait for them: `cancel()` on every asyncio task and
     `asyncio.gather`, a C# `CancellationToken`, an Eio switch, rust-tokio returning from
     `#[tokio::main]` without awaiting its tasks (dropping the runtime drops them), or a
     `closed` flag set on every channel at once (C++, Odin) followed by `join`. Every blocked
     send and receive fails at once, so no stage takes another number.

  With option 1 the stages may go on sieving in the background until the process ends. That is
  allowed: nothing waits for it. Printing may come before or after the shutdown, and the
  shutdown is part of the timed run.

  **Never close or drop only the last channel and then join.** A filter notices the closed
  channel only on its next send, and that needs one more number to get past every filter before
  it. So the pipeline goes on until every stage has found one more survivor, and the program
  waits for all of it. At `n = 800` that is 670,829 filter receives instead of about 333,000,
  with the generator running on to 13,432: twice the work. Measured at `bench`, Rust took
  0.98 s that way and 0.50 s returning without a join; Cheby took 40 ms in a `fiber::scope`
  against 35 ms with detached fibers.

  Two traps with option 1:

  - **Node.** Let the process end on its own: promises that never resolve do not keep it alive.
    Never call `process.exit`. Writes to a piped stdout are asynchronous on macOS, so exiting
    right after `console.log` can cut the output short.
  - **C++ with detached threads.** A blocked thread still uses its channel's mutex and condition
    variable after `main` returns. Keep every channel alive for its threads (a `shared_ptr`
    captured by each thread, or never freed), never in storage owned by `main`'s frame such as a
    `std::vector<Channel>`. Or use option 2: set a `closed` flag on every channel at once, then
    `join`.
- **Integers.** 64-bit signed integers, or the language's default integer if at least that wide,
  or arbitrary precision on the BEAM, Python and Ruby. The largest values are small (below
  `2^31` at every size), so TypeScript's `number` is exact.
- **Default runtime settings.** Keep the default thread count, scheduler count and pool size.
  Do not pin threads or set `GOMAXPROCS`, `+S` or `--threads`. Do not raise or lower thread
  stack sizes unless the default makes 802 threads fail; say so in `impl.toml` if you must.

### Pull protocol (Erlang, Elixir, Gleam)

Every stage that produces numbers answers requests. A request carries the requester's address,
which the requester sets up once, never per message.

```text
generator(i):
  receive {next, From}  ->  From ! {num, i};  generator(i + 1)

filter(Prime, Up):                   # Up is the stage before this one
  receive {next, From}  ->  From ! {num, pull(Prime, Up)};  filter(Prime, Up)

pull(Prime, Up):                     # the next number from Up that Prime does not divide
  Up ! {next, self()}
  receive {num, M}  ->  if M rem Prime == 0 then pull(Prime, Up) else M

main(n):
  Gen = spawn generator(2)
  loop n times with Cur = Gen:
    Cur ! {next, self()};  receive {num, P}
    Cur = spawn filter(P, Cur)
  print, then halt (or return from main)
```

Each handoff is a request and a reply, two messages. That is the price of a mailbox without
back-pressure, and it is what the BEAM rows measure. The protocol allows only one message in
flight in the whole pipeline, so the BEAM rows get no pipeline parallelism, while rendezvous
channels can overlap stages across cores. A prefetch-1 variant, where each stage keeps one
request outstanding upstream, was measured on OTP 29 and was slower (0.29 s became 0.47 s at
`n = 800`), so the strict pull stays.

- **Erlang, Elixir.** Plain `spawn`, `!`/`send` and `receive` with tagged tuples. No
  `gen_server:call`, which adds a monitor and a reference per message.
- **Gleam.** A subject can only be received by the process that created it. Each stage creates
  its request subject (of `Next(reply_to: Subject(Int))`) and its number subject once, at start,
  and hands its request subject to the spawner over a setup subject. Do not use `process.call` or
  `actor.call`, which create a new reply subject per message.

## Idiomatic primitive per language

The same table as `ping_pong`, with the changes this pipeline needs (OCaml, Swift, C++, the BEAM
rows). Standard library only, except the library rows (`gleam_erlang`, tokio, core.async, Eio).
Name a library in `impl.toml` under `libs`.

| Id                  | Tasks                                                       | Channels                                                                      |
| ------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `cheby`             | `fiber::spawn_detached`                                     | `channel::new::<Int>(0)`, `channel::send`, `channel::receive`                 |
| `gleam`             | `process.spawn` (gleam_erlang)                              | `Subject`s, pull protocol                                                     |
| `rust`              | `std::thread::spawn`, never joined                          | `std::sync::mpsc::sync_channel(0)`                                            |
| `rust-tokio`        | `#[tokio::main]` (multi-thread runtime), `tokio::spawn`     | `tokio::sync::mpsc::channel(1)`                                               |
| `go`                | goroutines                                                  | unbuffered `make(chan int)`                                                   |
| `zig`               | `std.Io.Threaded` (default), `Io.Group.concurrent`          | `std.Io.Queue(i64)` with a zero-length buffer, `putOne` and `getOne`          |
| `odin`              | `core:thread`                                               | `core:sync/chan`, unbuffered (or a rendezvous channel from `core:sync`)       |
| `cpp`               | `std::thread`                                               | a rendezvous channel built from `std::mutex` and `std::condition_variable`    |
| `erlang`            | `spawn`                                                     | `!` and `receive`, pull protocol                                              |
| `python`            | `asyncio.run`, `asyncio.create_task`, `await`               | `asyncio.Queue(maxsize=1)`                                                    |
| `java`              | virtual threads: `Thread.ofVirtual().start`                 | `java.util.concurrent.SynchronousQueue<Long>`, `put` and `take`               |
| `typescript`        | async functions                                             | the hand-written rendezvous `Channel<T>` of `ping_pong`                       |
| `swift`             | `Task { }`                                                  | a hand-written rendezvous actor channel (below)                               |
| `csharp`            | `Task.Run`, `await`                                         | `Channel.CreateBounded<long>(0)`, `WriteAsync` and `ReadAsync`                |
| `elixir`            | `spawn`                                                     | `send` and `receive`, pull protocol                                           |
| `scala`             | virtual threads: `Thread.ofVirtual().start`                 | `java.util.concurrent.SynchronousQueue[Long]`                                 |
| `clojure`           | virtual threads: `Thread/ofVirtual`                         | `java.util.concurrent.SynchronousQueue`, `.put` and `.take`                   |
| `clojure-coreasync` | `go` blocks                                                 | unbuffered `(chan)`, `>!` and `<!`                                            |
| `koka`              | `std/async`: nested `firstof` strands (no dynamic spawn)    | `std/async` `channel()`, `emit` and `receive`, pull protocol                  |
| `ocaml`             | `Thread.create` (the `threads.posix` library)               | `Event.new_channel`, `Event.sync (Event.send c v)` and `Event.receive`        |
| `ocaml-eio`         | `Eio_main.run`, `Eio.Fiber.fork` in a switch                | `Eio.Stream.create 0`, `Eio.Stream.add` and `Eio.Stream.take`                 |
| `nim`               | `createThread` (`--threads:on`, the default)                | `Channel[int]` opened with `open(ch, maxItems = 1)`, `send` and `recv`        |
| `ruby`              | `Thread.new`                                                | `SizedQueue.new(1)`, `push` and `pop`                                         |

Notes on the rows:

- **OCaml.** `ping_pong` uses domains, but OCaml allows only about 128 domains, so this pipeline
  uses system threads. `Event` channels are synchronous, so they are rendezvous channels. Exit
  with `exit 0` after printing. All systhreads of one domain share its runtime lock, so every
  handoff is also a lock handover. Expect this to be the slowest OS-thread row, about 5 to 7 s at
  `bench`.
- **Zig.** Zig 0.17 has no `std.Thread.Mutex` or `std.Thread.Condition`; blocking primitives live in
  `std.Io` and take an `io: Io` argument. Use the `io` that `main(init: std.process.Init)` receives
  (an `std.Io.Threaded`), or create a `std.Io.Threaded` with its default options. Start the
  generator and each filter with `group.concurrent(io, ...)` on one `Io.Group`. With the default
  `concurrent_limit` (unlimited), each concurrent task gets its own OS thread. Never use `io.async`
  or `Group.async`: their limit is the CPU count minus one, and past it the task runs inline on the
  caller, which deadlocks the pipeline. A `std.Io.Queue(i64)` initialised with an empty buffer is a
  rendezvous: `putOne` waits until a getter takes the value. Allocate each queue so its address
  never changes. Shut down with option 1: flush stdout after printing and call
  `std.process.exit(0)`, without `group.await`. Do not `close` the last queue and await the group:
  that doubles the work (see "Shut down"). A probe that shut down that way gave the right output at
  every size and ran `bench` in about 1.1 s, so expect about half of that. Threads get the 16 MiB
  default stack, about 12.8 GB of virtual memory at 802 threads, which macOS reserves lazily; the
  probe's peak resident set was 29 MB.
- **Swift.** `AsyncStream` never blocks a sender, so the infinite generator would buffer without
  bound. Write a small rendezvous `actor Channel`, the same shape as the TypeScript channel: a
  queue of waiting receivers (their `CheckedContinuation`s) and a queue of waiting senders (the
  value and its continuation), with no value slot. `swift-async-algorithms` is not the standard
  library.
- **Rendezvous channel** (C++, Odin without `core:sync/chan`). One mutex, one or two condition
  variables, and an optional value slot. `send` waits while the slot is full, fills it, signals,
  and then waits until a receiver has taken its value. `receive` waits while the slot is empty,
  takes the value and signals. Use `wait` in a loop on the condition, never a spin or a sleep.
  This differs from `ping_pong`'s one-slot channel: there the strict alternation makes capacity
  0 and 1 do the same work, but here a one-slot channel would let each OS thread run ahead of its
  consumer. A `closed` flag is fine if the shutdown sets it on every channel at once; so is
  ending the process with the threads blocked (see the C++ trap under "Shut down"). Expect these
  rows to be slower than Rust's: a condition-variable wait sleeps in the kernel at once, while
  Rust's zero-capacity `sync_channel` spins briefly before it parks.
- **Nim.** `Channel[int]` values must live in shared memory: allocate each with `allocShared0`
  and pass `ptr Channel[int]` to the threads. A running `Thread[T]` must never move, so do not
  `add` threads to a growing `seq`; preallocate it with `newSeq[Thread[...]](n + 1)`, or use
  `ref Thread[...]`. `import std/typedthreads`. System channels cannot be closed, so end with
  `quit(0)` after printing (option 1). A probe with Nim 2.2 in this shape ran `bench` in about
  1.0 s.
- **Koka** uses `std/async`, which has no dynamic spawn: each new filter starts in a nested
  `firstof(filter, rest of the sieve)`, and every await is forwarded through all enclosing
  strands, so one handoff costs O(pipeline depth). The row is measured but marked not comparable
  (`comparable = false` in its `impl.toml`) and is left out of the geometric means.
- **Thread counts.** The OS-thread rows (Rust, Zig, Odin, C++, OCaml, Nim, Ruby) run `n + 2`
  threads at once: 802 at `bench`. That is within macOS's default limit of 4096 per process.

## Output

Three lines, with a final newline:

```text
primes: <n>
last: <the n-th prime, or 0 when n = 0>
sum: <the sum of the first n primes>
```

For example, with `n = 10`:

```text
primes: 10
last: 29
sum: 129
```

## Size 0

`n = 0` creates the first channel, spawns the generator and shuts the pipeline down at once. The
generator's first send fails (or it stays blocked until the process ends). No filter is spawned.
The output is:

```text
primes: 0
last: 0
sum: 0
```

It must take the same path as any other size: no special case for 0.

## Sizes

| Size    | `n` | `last` | `sum`   | Handoffs | Of them from the generator | Filter receives (= `%` operations) | Rust, Apple M-series |
| ------- | --- | ------ | ------- | -------- | -------------------------- | ---------------------------------- | -------------------- |
| `zero`  | 0   | 0      | 0       | 0        | 0                          | 0                                  | ~3 ms                |
| `test`  | 100 | 541    | 24133   | 5,845    | 540                        | 5,745                              | ~30 ms               |
| `bench` | 800 | 6133   | 2277959 | 333,016  | 6,132                      | 332,216                            | ~0.4-0.6 s           |

Handoffs count every send before the shutdown: the generator's and the filters'. The counts are
for rendezvous channels. A capacity-1 channel lets each stage run one number ahead of its
consumer, so those rows do a few percent more filter work inside the timed run: Python with
`asyncio.Queue(maxsize=1)` made 351,610 filter receives at `bench` (+5.8%), and its generator
reached 6533. The exact outputs are in `expected/`. At `bench`, CPython with asyncio takes about
0.7 s. The size is set by the OS-thread rows: Rust took 0.40-0.60 s at `bench` on a loaded
machine (median 0.50 s), the low end of the CONVENTIONS range, and about 3.3 s at `n = 2000`,
while Cheby took 0.1 s there.

### Reading the Cheby and Go rows

At `bench`, Cheby and Go finish in tens of milliseconds, so start-up and noise decide their
order. Measured on a loaded M-series machine: Cheby 0.035 s in all, of which its size-0 run
(start-up and compiling the whole program, D-254's eager JIT) is 0.011 s; Go about 0.025 s in
all, 0.004 s of it at size 0, with a run-to-run spread of about ±18%.

Under CONVENTIONS, Cheby's run time is its `bench` median minus its size-0 median, an estimate,
while Go's run time is its whole median, start-up included. At this size the subtraction alone
is about a third of Cheby's total. So:

- Do not rank the Cheby and Go rows against each other at `bench`. Both are start-up-dominated.
- Wherever Cheby's run time appears, mark it as an estimate and show its total `bench` time
  next to it.

Raising `bench` to `n = 2000` would separate them (Cheby 0.1 s, Rust about 3.3 s, 2002 threads),
but it breaks the CONVENTIONS rule that Rust takes 0.5 to 1 s. That choice is left open for the
maintainer.
