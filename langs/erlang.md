# Erlang: guide for implementers

Erlang/OTP 29.1.2 (erts 17.1.1) from Homebrew, `erl`/`erlc` on `PATH` (`/opt/homebrew/bin`, no
version manager in between). rebar3 3.27.3 is installed for `compile_large`. `setup/erlang.sh`
checks both, and that OTP has the `json` module (OTP 27+). It fetches nothing.

## Project layout

One generic layout, set in `langs/erlang.toml`. Group agents only write sources.

```text
benchmarks/<bench>/erlang/
  main.erl        module `main`, exporting main/0 (the entry)
  other.erl ...   optional extra modules; every *.erl in the directory is compiled
  impl.toml       optional: libs, notes, or an override of build/clean/run
```

- `build`: `mkdir -p {build}/ebin && erlc +deterministic -o {build}/ebin *.erl`. One cold `erlc`
  process (`ERLC_USE_SERVER=false` in `env`, so the erlc compile server is never used). erlc's
  default optimisation is the release default. Do not add `+native` or other flags.
- `clean`: `rm -rf {build}/ebin`. erlc has no incremental mode, so every build recompiles every
  module anyway. hello_world: about 160 ms per clean build, about 100 ms per run (start-up).
- `run`: `erl -noshell -pa {build}/ebin -eval 'main:main(), halt(0).' -extra {args}`. This shape
  is fixed by the hello_world SPEC (BEAM notes) for every benchmark: only `-noshell`, `-pa`,
  `-eval`, `-extra`, default boot script, no emulator flags, `halt(0)` right after the entry.
- `artifact`: the `{build}/ebin` directory (the size of all beams).
- `env` also sets `ERL_CRASH_DUMP_SECONDS=0`, so a crash writes no `erl_crash.dump` into the
  source directory. A crash in `main` makes `erl` exit 1 ("Error! Failed to eval").

## Writing main.erl

```erlang
%% One-line description of the program.
-module(main).
-export([main/0]).

main() ->
    [Arg | _] = init:get_plain_arguments(),   % strings after -extra, e.g. ["21"]
    N = list_to_integer(Arg),
    io:put_chars(Output).                     % Output: an iolist built up front
```

- Arguments: `init:get_plain_arguments()` returns the `-extra` arguments as strings. A file path
  argument (`{data}/...`) arrives already expanded.
- `main/0` must return only when all output is written. `halt(0)` runs right after it and kills
  every other process, so a concurrency benchmark must wait (`receive`) for its workers' results
  before returning. Output written with `io:format`/`io:put_chars` is complete when the call
  returns, and `halt(0)` flushes the port.
- Compile warnings show up in `build/erlang/<bench>/build.log`. Keep them at zero
  (unused variables, `-compile({no_auto_import, [...]})` when a function clashes with a BIF).

## Building and running by hand

```sh
python3 runner/run.py verify -l erlang -b nbody --sizes zero,test,bench --diff

# or by hand, from benchmarks/<bench>/erlang/
B=../../../build/erlang/<bench>
mkdir -p $B/ebin && ERLC_USE_SERVER=false erlc +deterministic -o $B/ebin *.erl
erl -noshell -pa $B/ebin -eval 'main:main(), halt(0).' -extra 10
```

## Third-party dependencies

None should be needed. The only library CONVENTIONS allows is a JSON library when the standard
library has none, and OTP 29 ships `json` (`json:decode/1,3`, `json:encode/1,2`,
`json:encode_key_value_list/2`). json_roundtrip uses it and names it in `impl.toml`, for example
`libs = []` and `notes = "OTP json module"`.

If a dependency ever became necessary, the pattern would be: a rebar3 project fetched and compiled
once by `setup/erlang.sh` into `build/erlang-deps/` (with `REBAR_BASE_DIR`), an `impl.toml`
whose `run` adds `-pa {root}/build/erlang-deps/default/lib/<dep>/ebin`, and a `clean` that leaves
that directory alone. Ask before doing it: it would also need setup to stay offline-safe.

## compile_large (rebar3)

Its SPEC asks for a rebar3 project (`src/m0000.erl` ...), because `rebar3 compile` compiles
modules in parallel and `erlc *.erl` is serial. A layout that works here, as an `impl.toml`
override (the project dir is what `gen.py` writes):

```toml
build = "REBAR_BASE_DIR={build}/_build REBAR_OFFLINE=1 rebar3 compile"
clean = "rm -rf {build}/_build"
run = "erl -noshell -pa {build}/_build/default/lib/<app>/ebin -eval 'main:main(), halt(0).' -extra {args}"
```

- The project needs `rebar.config` (`{erl_opts, [deterministic]}.`) and
  `src/<app>.app.src` with a `description` (rebar3 warns without one).
- With no deps, `rebar3 compile` touches no network. rebar3 is an escript; no daemon survives.
- `_build` holds only the project's own app plus rebar3's source DAG
  (`_build/default/lib/.rebar3`), both derived from the project, so `clean` removes all of it.
- rebar3 prints "Setting httpc proxy ..." lines because of the machine's proxy env. Harmless.

## Gotchas

- **Output cost.** Each `io:format`/`io:put_chars` call is a message round trip to the io
  server, about 10 us. 200 000 lines one call each took about 2 s; the same lines as one iolist
  in one `io:put_chars` took 0.15 s. For many lines, build an iolist (`[integer_to_binary(X),
  $\n]` per line) and write it once, or in a few chunks. Use `integer_to_binary/1` /
  `integer_to_list/1` rather than `io_lib:format` in hot paths.
- **stdout encoding** under `-noshell` is `unicode`. Output here is ASCII, so lists, binaries and
  `~s` all print as is.
- **Integers are arbitrary precision.** There is no wrapping. A 64-bit LCG or xorshift must mask
  explicitly: `(A * X + C) band 16#FFFFFFFFFFFFFFFF`; for signed 64-bit semantics convert by
  hand (`if V >= 1 bsl 63 -> V - (1 bsl 64)`). Small integers are 60-bit; anything larger is a
  heap bignum, so 64-bit RNG arithmetic allocates and is slower. That is the language, not a bug.
  `bsl` does not truncate either. `div`/`rem` truncate toward zero; there is no floored mod
  operator (use `((A rem B) + B) rem B`).
- **Rounding.** `round/1` rounds half away from zero (`round(2.5) = 3`, `round(-2.5) = -3`),
  which is exactly CONVENTIONS' rule. `trunc/1` truncates. `/` always gives a float; `div` is
  integer division.
- **Floats raise on division by zero** (`badarith`), and there are no NaN or infinity values.
  Arrange the arithmetic so it cannot happen (the mandelbrot SPEC says how).
- **Recursion.** No stack limit to worry about: process stacks grow on the heap. Prefer tail
  recursion with accumulators for long loops; body recursion over a list of a few million
  elements is fine but uses memory.
- **Data structures.** Maps for hash maps (persistent, `maps:update_with/4` for counting),
  `gb_trees`/`gb_sets` for ordered structures, tuples with `element/2` for fixed small records,
  `array` only where a spec wants indexed updates and lists do not fit. `setelement/3` copies the
  whole tuple. Sorting: `lists:sort/2` with a comparison fun, or `lists:keysort/2`.
- **Binaries for text.** `file:read_file/1` returns a binary;
  `binary:split(Bin, Seps, [global, trim_all])` splits without copying. Map keys can be binaries.
- **JSON.** `json:decode/1` returns maps (keys are binaries), which lose key order;
  `json:encode/1` writes maps in sorted key order. Where a SPEC fixes key order, encode ordered
  key-value lists with `json:encode/2` and a custom encoder calling
  `json:encode_key_value_list/2` (see json_roundtrip SPEC). `json:encode` returns an iolist.
- **Concurrency.** Plain `spawn`, `!` and `receive` (no gen_server) as the specs say. The runtime
  keeps its default scheduler count (8 here); do not pass `+S`.
- **Module name `main`** is fine; avoid naming extra modules after OTP modules (`lists`, `json`,
  `queue`, ...), which would clash in the code path.
