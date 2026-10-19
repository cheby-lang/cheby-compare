# Gleam in cheby-compare

Notes for writing the Gleam implementations. Gleam 1.19.2 on the Erlang target, Erlang/OTP 29,
gleam_stdlib 1.0.5. The config is `langs/gleam.toml` and the setup script is `setup/gleam.sh`.

## Project layout

Every benchmark uses the same layout, so normally you only write sources:

```text
benchmarks/<bench>/gleam/
  gleam.toml       name = "main", target = "erlang", [dependencies]
  manifest.toml    pinned versions, written by Gleam (see "Adding a dependency")
  src/main.gleam   pub fn main() -> Nil, plus any other modules in src/
  impl.toml        optional: libs = [...], notes = "...", or a key override
```

Copy `benchmarks/hello_world/gleam/gleam.toml` and `manifest.toml` as a starting point. The
package must be named `main` and the entry module `src/main.gleam` must export `pub fn main()`,
because the run command calls `main:main()`. Other modules go in `src/` as usual, for example
`src/tree.gleam`, imported as `import tree`.

Do not run `gleam` inside `benchmarks/<bench>/gleam/`. Gleam would create a `build/` directory
there, and the repository's `.gitignore` does not cover it. If you do it by mistake, delete it.

## What the runner does

- **build**: copies `gleam.toml`, `manifest.toml` and `src/` into `build/gleam/<bench>/proj/`,
  keeping mtimes, then runs one cold `gleam build --target erlang` there. Gleam has no daemon or
  compile server.
- **clean**: `rm -rf build/gleam/<bench>/proj/build/dev/erlang/main`. This removes only this
  package's compiled output. gleam_stdlib and any hex dependency stay compiled, and the downloaded
  packages stay. After `clean`, `build` recompiles only `main`. On hello_world that takes about
  0.19 s, and most of it is Gleam's fixed cost: a no-op build takes about 0.18 s.
- **run**: `erl -noshell -pa build/gleam/<bench>/proj/build/dev/erlang/*/ebin -eval 'main:main(), halt(0).' -extra {args}`.
  These are the same beams that `gleam export erlang-shipment` ships, run with plain `erl` and
  default flags, as CONVENTIONS "Deployable form" and the hello_world BEAM notes require.
- **artifact**: `.../dev/erlang/main/ebin`, which holds the program's own beams.

Why not `gleam export erlang-shipment`: the export always deletes `build/prod` and recompiles
every dependency, gleam_stdlib included, so no `clean` could keep the standard library compiled.
Dev and prod builds pass erlc the same options (`[debug_info]`), and their `.beam` files are
byte-identical (checked).

## Building and running by hand

From the repository root:

```sh
python3 runner/run.py verify -l gleam -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py build -l gleam -b <bench>       # build only; the log is build/gleam/<bench>/build.log
```

To run one size yourself after a build:

```sh
P=build/gleam/<bench>/proj
erl -noshell -pa $P/build/dev/erlang/*/ebin -eval 'main:main(), halt(0).' -extra 10
```

For a quick type check while you edit, run `cd build/gleam/<bench>/proj && gleam check`. Copy the
sources there first, or let `run.py build` do it. Then copy any change back to `benchmarks/`.

A panic (`let assert`, `panic`) prints `Error! Failed to eval: ...` with the Gleam error map and
exits 1. `ERL_CRASH_DUMP_SECONDS=0` in the config stops the crash from writing `erl_crash.dump`.

## Adding a dependency

The only third-party packages allowed are `gleam_erlang` and `gleam_otp`, for the concurrency
benchmarks, and `gleam_json`, for json_roundtrip (CONVENTIONS, "Standard library first"). Do not
use `argv` or `simplifile`: the FFI snippets below cover arguments and file reading with
gleam_stdlib alone.

1. Add the line to `[dependencies]` in your `gleam.toml`. These versions are already in Gleam's
   hex cache:

   ```toml
   gleam_erlang = ">= 1.0.0 and < 2.0.0"   # 1.3.0
   gleam_otp = ">= 1.0.0 and < 2.0.0"      # 1.3.0
   gleam_json = ">= 3.0.0 and < 4.0.0"     # 3.1.0
   ```

2. Run `setup/gleam.sh lock <bench>`. It resolves the versions in the staging directory and
   writes `benchmarks/<bench>/gleam/manifest.toml`. Resolving needs the network, even when the
   tarballs are cached.
3. Name the package in `impl.toml`, for example `libs = ["gleam_json"]`.

When `manifest.toml` exists, `build` runs offline. Running `setup/gleam.sh` with no arguments
stages every Gleam benchmark and downloads its locked packages. It is idempotent.

## Arguments and files without extra packages

Call Erlang directly through `@external`. These declarations need nothing but gleam_stdlib:

```gleam
import gleam/bit_array
import gleam/int
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

// Erlang returns {ok, Bin} | {error, Reason}, which is how Gleam represents a Result.
@external(erlang, "file", "read_file")
fn read_file(path: String) -> Result(BitArray, reason)

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)
  let assert Ok(bits) = read_file("...")
  let assert Ok(text) = bit_array.to_string(bits)
  ...
}
```

`init:get_plain_arguments()` returns exactly the arguments after `-extra`.

## Gotchas

- **Integers are arbitrary precision.** Nothing wraps. For a 64-bit LCG or xorshift, mask after
  every step with `int.bitwise_and(x, 0xFFFFFFFFFFFFFFFF)`. If the spec wants a signed
  interpretation, convert it by hand. `int.bitwise_shift_left` grows without limit, so mask that
  too. Integers up to about 60 bits, signed, are immediate. Beyond that a value is a heap bignum,
  which is slower, so mask early.
- **Division never crashes.** `a / 0` is `0` for Int and `a /. 0.0` is `0.0` for Float. `/`
  truncates toward zero (`-7 / 2 == -3`) and `%` is the truncating remainder (`-7 % 2 == -1`).
  For floored behaviour use `int.floor_divide` or `int.modulo`, which return a `Result`.
- **Float to output integer:** `float.round(x *. 1000.0)` rounds half away from zero (it is
  Erlang's `round/1`), which is what CONVENTIONS asks for. `float.truncate` and `int.to_float` are
  the other conversions. Float operators are separate: `+.`, `-.`, `*.`, `/.`, `<.`.
- **No loops and no mutation.** Use recursion. Tail calls are optimised. Deep non-tail recursion
  is fine on BEAM: a 10-million-deep non-tail `sum` runs without trouble, since the stack grows on
  the heap. Accumulate into lists and `list.reverse` them at the end.
- **No arrays in the standard library.** Use `List`, tuples, or `gleam/dict` (a persistent map,
  O(log n)). If a spec calls for an indexed mutable array (fannkuch), the idiomatic choices are
  lists, a dict keyed by index, or Erlang's `array` module through `@external`. Pick one and
  record it in `notes`.
- **Output:** `io.println` writes one line. For many lines, build a `string_tree` (or a list of
  strings joined with `string.join(_, "\n")`) and print it once. Unicode prints correctly under
  `-noshell` without `io:setopts`.
- **`main` runs in the `-eval` process**, not inside Gleam's `main@@main:run` wrapper (the
  hello_world SPEC fixes the run shape). The wrapper's application start does not happen, and
  nothing in gleam_erlang or gleam_otp needs it: `process.spawn`, `process.new_subject`,
  `process.send` and `process.receive(subject, within: ms)` work as usual. A subject can be
  received from only by the process that created it. Create the reply subject in the receiving
  process and send it to the other side. `process.spawn` links the new process. Use
  `process.spawn_unlinked` when a linked crash should not take `main` down.
- **The `-eval` process traps exits.** erl's `-eval` process starts with `trap_exit = true`, while
  Gleam's own entry wrapper (`main@@main:run_module`) sets `process_flag(trap_exit, false)` before
  it calls `main()`. With trapping on, every linked child that exits leaves an `{'EXIT', ...}`
  message in `main`'s mailbox, and selective receives then scan a growing queue. spawn_many calls
  `process.trap_exits(False)` at the start of `main` to restore what the shipment entrypoint gives.
  ping_pong and prime_sieve do not need it. Check the Erlang and Elixir rows for the same effect.
- **`/.` carries a division-by-zero guard.** Gleam compiles `a /. b` to
  `case B of +0.0 -> +0.0; -0.0 -> -0.0; V -> A / V end`, which stops BEAM keeping the values in
  float registers, and Gleam cannot ask for inlining. On spectral_norm this makes the Gleam row
  about 2x slower than the Erlang row in user CPU time, and nbody about 1.5x. That is a language
  cost, not an implementation choice: writing A(i, j) out by hand gained only about 7%.
- **Constant subterms are literals.** `Node(Empty, Empty)` compiles to the BEAM literal
  `{node, empty, empty}`, so every binary_trees leaf is one shared constant and is never allocated.
  The Erlang row does the same. This is reported against the binary_trees SPEC ("one node is one
  separate heap allocation"). The code stays idiomatic until the SPEC settles it for all BEAM and
  ML rows.
- **gleam_json 3.x** encodes and decodes through OTP's own `json` module. `json.parse(text,
  decoder)` needs a `gleam/dynamic/decode` decoder. To walk an arbitrary document, write a
  recursive decoder with `decode.one_of` over a custom JSON type, and use `decode.recursive` for
  the self-reference.
- **Warnings** go to stderr during `build`, which is fine. Keep the program's stderr empty at run
  time.
- `extensions` counts `.gleam` and `.erl` for lines of code, with `//` as the comment prefix.
  Prefer `@external` to OTP functions over adding a `.erl` FFI file.
