# Elixir: guide for implementers

Elixir 1.20.4 on Erlang/OTP 29 (erts 17.1.1), both from Homebrew: `elixir`, `mix` and `erl` on
`PATH` (`/opt/homebrew/bin`, no version manager in between). `setup/elixir.sh` checks the
toolchain, that Elixir is 1.18+ (built-in `JSON`), that Elixir's ebin is where `run` expects it,
and the `-pa` ordering `run` relies on. It fetches nothing unless a project declares hex deps.

## Project layout

One generic layout, set in `langs/elixir.toml`. Group agents only write sources.

```text
benchmarks/<bench>/elixir/
  mix.exs        Mix project, app `:main` (copy hello_world's, change nothing but deps)
  lib/main.ex    defmodule Main with a public main/0 (the entry)
  lib/*.ex       optional extra modules
  impl.toml      optional: libs, notes, or an override of build/clean/run
```

`mix.exs`, the same for every benchmark:

```elixir
defmodule Main.MixProject do
  use Mix.Project

  def project do
    [
      app: :main,
      version: "1.0.0",
      elixir: "~> 1.20",
      deps: []
    ]
  end
end
```

- `build`: `MIX_BUILD_ROOT={build}/_build MIX_DEPS_PATH={build}/deps mix compile`, with
  `MIX_ENV=prod` from `env`. One cold `mix` process (Mix has no daemon or compile server). It
  compiles `lib/` and consolidates protocols, as a release does. Nothing is written into the
  source dir: `_build` and `deps` live under `build/elixir/<bench>/`.
- `clean`: `rm -rf {build}/_build/prod/lib/main`, the app's beams, its `.mix` manifests and its
  `consolidated/` protocols. Compiled deps (if any) stay. hello_world: about 0.31 s per clean build
  (most of it is Mix start-up; a no-op `mix compile` takes 0.26 s), about 0.10 s per run.
- `run`: `erl -noshell -pa <elixir ebin> {build}/_build/prod/lib/*/ebin
  {build}/_build/prod/lib/main/consolidated -eval "'Elixir.Main':main(), halt(0)." -extra {args}`.
  The shape is fixed by the hello_world SPEC (BEAM notes) for every benchmark: only `-noshell`,
  `-pa`, `-eval`, `-extra`, default boot script, no emulator flags, `halt(0)` right after the
  entry. Not an escript and not `mix run`.
- `artifact`: `{build}/_build/prod/lib/main/ebin` (the program's own beams).

## Writing lib/main.ex

```elixir
defmodule Main do
  @moduledoc "One-line description of the program."

  def main do
    [arg | _] = :init.get_plain_arguments()   # charlists after -extra, e.g. [~c"21"]
    n = arg |> List.to_string() |> String.to_integer()
    IO.write(output)                           # output: iodata built up front
  end
end
```

- **Arguments: use `:init.get_plain_arguments()`, not `System.argv()`.** `System.argv()` raises
  (`ArgumentError`, missing ETS table) because the `elixir` application and its CLI are not
  started by this run shape. Convert with `List.to_string/1`. A `{data}/...` path arrives
  expanded.
- The `elixir` application is not started (starting it cost about 15% of hello_world's start-up,
  and Erlang/Gleam do not start theirs either). Everything in Elixir's own ebin works without it:
  `Enum`, `Stream`, `Map`, `String`, `Regex`, `JSON`, `File`, `Task`, `Task.async_stream`, `Agent`,
  `inspect`, `IO.inspect`. Only Elixir's ebin is on the path: **no `Logger`, `EEx`, `ExUnit` or
  `Mix`** at run time.
- `main/0` must return only when all output is written. `halt(0)` runs right after it and kills
  every other process, so a concurrency benchmark must wait for its workers (`Task.await_many`,
  `receive`) before returning. `IO.puts`/`IO.write` return after the data is written.
- Compile warnings show up in `build/elixir/<bench>/build.log` (including Elixir 1.20's type
  checker warnings). Keep them at zero. Format with `mix format` defaults.

## Building and running by hand

```sh
python3 runner/run.py verify -l elixir -b nbody --sizes zero,test,bench --diff

# or by hand, from benchmarks/<bench>/elixir/
B=$(cd ../../.. && pwd)/build/elixir/<bench>
MIX_ENV=prod MIX_BUILD_ROOT=$B/_build MIX_DEPS_PATH=$B/deps mix compile
erl -noshell -pa /opt/homebrew/opt/elixir/lib/elixir/lib/elixir/ebin $B/_build/prod/lib/*/ebin \
  $B/_build/prod/lib/main/consolidated -eval "'Elixir.Main':main(), halt(0)." -extra 10
```

`MIX_BUILD_ROOT` must be absolute. Forgetting it makes Mix write `_build/` into the source dir;
delete it if that happens (it is git-ignored, but it is not where `run` looks).

## Third-party dependencies

None should be needed. CONVENTIONS allows a library only for JSON when the standard library has
none, and Elixir 1.18+ ships `JSON` (`JSON.decode!/1`, `JSON.encode!/1`,
`JSON.encode_to_iodata!/1`), plus OTP's `:json`. json_roundtrip should use them and say so in
`impl.toml`, e.g. `libs = []` and `notes = "built-in JSON module"`.

If a hex dependency ever became necessary (ask first), the setup already supports it:

1. Add it to `deps` in `mix.exs`.
2. Lock it once, online: `mix local.hex --force` (only if Hex is not installed yet), then from
   the project dir `MIX_ENV=prod MIX_BUILD_ROOT=$B/_build MIX_DEPS_PATH=$B/deps mix deps.get`.
   This writes `mix.lock` into the project dir; keep it next to `mix.exs`.
3. Run `setup/elixir.sh`. For every project with a `mix.lock` it runs `mix deps.get
   --check-locked` and `mix deps.compile` into `build/elixir/<bench>/{deps,_build}`.
4. `build` then compiles offline (`HEX_OFFLINE=1`), `clean` keeps `_build/prod/lib/<dep>`, and
   `run` already puts `_build/prod/lib/*/ebin` on the path. Name the library in `impl.toml`.

## compile_large

The generated project uses the same layout (`mix.exs` with app `:main`, `lib/main.ex` with
`Main.main/0`, `lib/m0000.ex` ...), so the default `build`/`clean`/`run` apply unchanged. There
`{build}` is `build/elixir/compile_large/out-<size>`, which is why the Mix paths sit in the
`build` command and not in `env` (the runner fills `{build}` in `env` with the implementation's
build dir). Mix compiles modules in parallel by default.

## Gotchas

- **Output cost.** Each `IO.puts`/`IO.write` call is a message round trip to the io server.
  100 000 lines one call each took about 0.6 s; the same lines as one iodata list in one
  `IO.write` took 10 ms. Build iodata (`[Integer.to_string(x), ?\n]` per line) and write once or
  in a few chunks. Avoid string interpolation in hot output loops.
- **Integers are arbitrary precision.** No wrapping. A 64-bit LCG or xorshift must mask:
  `import Bitwise`, then `(a * x + c) &&& 0xFFFFFFFFFFFFFFFF` (or `band/2`); `<<<` does not
  truncate either. For signed 64-bit semantics convert by hand. Values above 60 bits are heap
  bignums, so 64-bit RNG arithmetic allocates; that is the platform.
- **Division.** `/` always returns a float; `div/2` and `rem/2` truncate toward zero
  (`div(-7, 2) = -3`, `rem(-7, 2) = -1`); `Integer.mod/2` and `Integer.floor_div/2` floor.
- **Rounding.** `round/1` rounds half away from zero (`round(2.5) = 3`, `round(-2.5) = -3`),
  exactly CONVENTIONS' rule, and returns an integer. `trunc/1` truncates. `Float.round/2` returns
  a float, so do not use it for output.
- **Floats raise on division by zero** (`ArithmeticError`), and there is no NaN or infinity.
  Arrange the arithmetic so it cannot happen (the mandelbrot SPEC says how).
- **Recursion.** No stack limit: process stacks grow on the heap (body recursion 10 million deep
  works). Prefer tail recursion with accumulators for long loops; multi-clause functions with
  guards are the idiomatic loop.
- **Data structures.** `Map` for hash maps (`Map.update/4` for counting), `:gb_trees`/`:gb_sets`
  for ordered structures, tuples with `elem/2`/`put_elem/3` for small fixed records (`put_elem`
  copies the tuple), structs for named records, `:array` only where a spec wants indexed updates.
  Sorting: `Enum.sort_by/3` or `Enum.sort/2` with a comparator (both stable).
- **Text.** `File.read!/1` gives a binary; `String.split(bin, seps, trim: true)` or
  `:binary.split(bin, seps, [:global, :trim_all])` split it. Binaries make good map keys.
  `String.*` functions are Unicode-aware and slower than `:binary` ones on ASCII data.
- **JSON.** `JSON.decode!/1` returns maps (binary keys), so key order is lost. `JSON.encode!/1`
  writes small maps (32 keys or fewer) in sorted key order, which is not insertion order. Where a
  SPEC fixes key order, write ordered objects yourself: a struct with a `JSON.Encoder`
  implementation, or `:json.encode_key_value_list([{"b", 1}, {"a", 2}], &:json.encode_value/2)`
  (gives `{"b":1,"a":2}`). Encoders return iodata; `JSON.encode_to_iodata!/1` avoids flattening.
  Floats encode in shortest round-trip form (`1.5e20`, `0.1`).
- **Protocols.** `Enum` and friends dispatch through protocols. `run` puts the build's
  `consolidated/` dir ahead of Elixir's ebin (unconsolidated protocols are much slower). If you
  change `run` in an `impl.toml`, keep `consolidated` last in the `-pa` list (OTP 29 reverses it).
- **Concurrency.** `spawn`/`send`/`receive` or `Task` as each SPEC says. The runtime keeps its
  default scheduler count; do not pass `+S`.
- **The main process traps exits.** Under the `erl -noshell ... -eval` run shape the process that
  calls `Main.main/0` has `trap_exit` set (`process_info(self(), trap_exit)` returns
  `{trap_exit,true}`). Every linked process that ends (`Task.async`, `spawn_link`) then leaves an
  `{:EXIT, pid, reason}` message in main's mailbox, and later `receive`s scan past them all.
  spawn_many took 84 s instead of 0.35 s this way. A program that uses `Task.async` or
  `spawn_link` should call `Process.flag(:trap_exit, false)` first thing in `main/0`.
- **Float code is less specialised than erlc's.** Elixir compiles through Core Erlang
  (`from_core`), and the BEAM it emits for float-heavy loops keeps `is_tuple`/`test_arity` checks
  and generic `gc_bif` arithmetic where erlc emits float-register `fsub`/`fmul`. nbody runs about
  30-35% slower than the Erlang version with the same algorithm and data shape. Rewriting the
  loop (`for`, `:lists.reverse`) did not change this. It is the toolchain, not the code.
- **Module names.** The entry is `Main`; extra modules can be anything not clashing with Elixir
  or OTP modules (`Enum`, `JSON`, `:lists` ...). Elixir modules are atoms `Elixir.Foo`, so
  `Main` cannot clash with Erlang's or Gleam's lowercase `main`.
