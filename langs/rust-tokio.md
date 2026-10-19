# Rust (tokio) in cheby-compare

The library variant of the `rust` row (CONVENTIONS, "Library variants"). It exists only for
`ping_pong`, `spawn_many` and `prime_sieve`. The compiler is the same rustc 1.99 as `rust`, and
the library is [tokio](https://tokio.rs) 1.53.3.

## Project layout

One Cargo crate per implementation, in `benchmarks/<bench>/rust-tokio/`:

```text
benchmarks/<bench>/rust-tokio/
  Cargo.toml   [package] name = "main", edition = "2024"; [dependencies] tokio = { version = "1", features = [...] }
  Cargo.lock   pins tokio and its dependencies; committed
  src/main.rs  the program, starting with a //! comment that says what it does
  impl.toml    libs = ["tokio"] and notes
```

- **Features.** `rt-multi-thread` and `macros` always, plus `sync` for the channel benchmarks
  (`ping_pong`, `prime_sieve`). Nothing else: no `full`, no `parking_lot`.
- **Pinning.** Each crate's `Cargo.lock` pins tokio. All three must pin the same version, because
  the `version` command in `langs/rust-tokio.toml` reads it from `ping_pong`'s lockfile only.
  `setup/rust-tokio.sh` fails if they disagree. To move to a new tokio, run `cargo update -p tokio`
  in all three crates, then run the setup script again.
- **Runtime.** `#[tokio::main]`, which is the multi-threaded runtime with its default worker
  count, one per core. Never set `worker_threads` or `TOKIO_WORKER_THREADS`, and never use
  `flavor = "current_thread"` (SPEC, "Default threads").
- **Channels.** `tokio::sync::mpsc::channel(1)`. tokio's mpsc has no capacity 0, so 1 is the
  closest to a rendezvous (SPEC, "Rendezvous where possible").

## Build, clean, run (langs/rust-tokio.toml)

- `setup/rust-tokio.sh` runs `cargo fetch --locked` in each crate, so tokio and its dependencies
  sit in cargo's registry cache. It also checks that the three lockfiles agree.
- `build`: `cargo build --release --quiet --offline --locked --target-dir {build}`. `--offline`
  needs the fetch above. `--locked` makes a build fail instead of re-resolving and rewriting
  `Cargo.lock`, so the tokio that is built is the pinned one.
- `clean`: removes only the `main` crate's outputs from the per-implementation target directory.
  tokio stays compiled, so the timed build compiles and links only the program (CONVENTIONS,
  third-party libraries are not part of compile time).
- `run` and `artifact`: `{build}/release/main`.

By hand, from the repository root:

```sh
sh setup/rust-tokio.sh
python3 runner/run.py verify -l rust-tokio -b <bench> --sizes zero,test,bench --diff
```

## Gotchas

- **`main` is not a worker.** `#[tokio::main]` runs its future through `block_on` on the main OS
  thread, not on one of the runtime's workers. Work done directly in `main` therefore crosses
  between a worker and the parked main thread, which costs an OS park and unpark, and every
  `tokio::spawn` from it goes through the runtime's global inject queue.
  - `ping_pong`'s SPEC forbids this for task A: main spawns B and then A, and only awaits their
    `JoinHandle`s.
  - `spawn_many` and `prime_sieve` follow their SPEC rows, which put the spawner (and, in
    `prime_sieve`, the driver loop that receives each prime) in `main`. Their `impl.toml` notes
    say so, because it is measurably slower than running the same loop in a spawned task.
- **Shutdown.** `prime_sieve` uses SPEC shutdown option 2: `main` returns without awaiting its
  tasks, and dropping the runtime drops them all.
- **Arguments and output.** As for `rust`: parse `env::args().nth(1)`, print with `println!`.
  Size 0 must take the same code path.
