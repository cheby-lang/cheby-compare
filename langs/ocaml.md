# OCaml in cheby-compare

OCaml 5.5.1 from Homebrew (`/opt/homebrew/bin/ocamlopt`), **no flambda** (`ocamlopt -config |
grep flambda` says `false`), so there are no `-O2`/`-O3` levels: ocamlopt's normal native code
is the release build. The build tool is dune 3.24.2, and the third-party libraries come from a
private opam switch that `setup/ocaml.sh` makes on top of the Homebrew compiler
(`ocaml-system.5.5.1`):

| Package    | Version | Used by                                              |
| ---------- | ------- | ---------------------------------------------------- |
| `dune`     | 3.24.2  | every benchmark (`build`)                            |
| `yojson`   | 3.0.0   | json_roundtrip (CONVENTIONS allows `yojson` for JSON) |
| `eio_main` | 1.6     | the `ocaml-eio` variant (ping_pong, spawn_many, prime_sieve) |

The opam root is `~/.cache/cheby-compare/opam`, the switch `cheby-compare`, its prefix
`~/.cache/cheby-compare/opam/cheby-compare`. `setup/ocaml.sh` is idempotent (about 1 s when
everything is there) and recreates the switch if Homebrew upgrades OCaml. After it has run,
builds are offline. Everything else (`threads.posix`, `unix`, `str`, `Domain`, `Mutex`,
`Condition`, `Event`, `Hashtbl`, `In_channel`) is in the compiler's own distribution and needs no
setup.

## Project layout

One dune project per implementation, in `benchmarks/<bench>/ocaml/`:

```text
benchmarks/<bench>/ocaml/
  dune-project   (lang dune 3.0)                       exactly this one line
  dune           (executable (name main) ...)          see below
  main.ml        the program; more modules (foo.ml) may sit next to it
  impl.toml      optional: libs, notes, or overrides of langs/ocaml.toml keys
```

Copy `benchmarks/hello_world/ocaml/dune-project` and `dune` as they are. The executable must be
named `main`, because `run` is `{build}/_build/default/main.exe`. With libraries, the `dune` file
becomes:

```lisp
(executable
 (name main)
 (libraries threads.posix))
```

Do not add `(ocamlopt_flags ...)`, `-O3`, `-unboxed-types`, `-unsafe` or `(modes ...)`. Keep
dune's release flags. Do not add a `.opam` file, a `dune-workspace` or a `(package ...)` stanza.

Start `main.ml` with a `(* ... *)` comment saying what the program does. **Lines of code** count
every line not starting with `(*`, so write each comment line as its own `(* ... *)` (a comment
spread over several lines counts its continuation lines as code). `.mli` files are optional and
counted too; dune makes an empty interface for `main` itself. No `ocamlformat` is installed;
format by hand in its default style (2-space indent, `let () =` entry point).

## Build, clean, run (langs/ocaml.toml)

- `env`: `PATH` gets the switch's `bin` first (for `dune`; `ocamlopt` stays Homebrew's), and
  `OPAM_SWITCH_PREFIX` points at the switch, which is how dune finds `yojson` and `eio`. No
  `opam exec` proxy.
- `build`: `dune build --root . --build-dir {build}/_build --profile release --cache disabled`.
  `--build-dir` keeps `_build` out of the source tree (`build/ocaml/<bench>/_build`).
  `--cache disabled` turns off dune's shared cache in `~/.cache/dune`, which would make a build
  after `clean` a cache hit. dune runs no daemon outside `--watch`.
- `clean`: `rm -rf {build}/_build`. The stdlib and the switch's libraries stay compiled where
  they are installed, so the timed build compiles and links only this program.
- `run`: `{build}/_build/default/main.exe {args}`. `artifact`: the same file.

Measured on hello_world (busy machine): clean → build ≈ 145 ms (ocamlc for the `.cmi`, ocamlopt
for the `.o`, ocamlopt link), a no-op rebuild ≈ 21 ms, start-up ≈ 1.7 ms, 385 KB executable.
A ~20 ms "build" after `clean` would mean the clean did not work.

By hand, from the repository root:

```sh
python3 runner/run.py verify -l ocaml -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py build -l ocaml -b <bench>

# or manually:
export OPAM_SWITCH_PREFIX=$HOME/.cache/cheby-compare/opam/cheby-compare
export PATH=$OPAM_SWITCH_PREFIX/bin:$PATH
cd benchmarks/<bench>/ocaml
mkdir -p ../../../build/ocaml/<bench>      # the runner does this; dune refuses otherwise
dune build --root . --build-dir $PWD/../../../build/ocaml/<bench>/_build --profile release --cache disabled
../../../build/ocaml/<bench>/_build/default/main.exe 10
```

`--display short` on the dune command shows each compiler step.

## Adding a third-party library

Only JSON (`yojson`, already installed) and the `ocaml-eio` variant (`eio_main`, already
installed) may use one (CONVENTIONS "Standard library first").

1. If the package is not in the switch yet, add it to `PACKAGES` in `setup/ocaml.sh` and run
   `setup/ocaml.sh` (needs the network once).
2. Add the findlib name to `(libraries ...)` in the benchmark's `dune` file.
3. Name it in `benchmarks/<bench>/ocaml/impl.toml`, e.g. `libs = ["yojson 3.0.0"]`.

## Gotchas

- **63-bit `int`.** `int` is 63-bit (`max_int` = 4611686018427387903) and wraps mod 2^63. It is
  right for counters, sums and checksums the specs bound below 2^62, but **wrong for 64-bit
  generators** (LCG, xorshift, FNV, splitmix): use `Int64` (`Int64.mul`, `add`, `logxor`,
  `shift_left`, `shift_right_logical`), which wraps mod 2^64. Unsigned helpers:
  `Int64.unsigned_rem`, `unsigned_div`, `unsigned_compare`, `unsigned_to_int`, and `Printf "%Lu"`
  for printing a `uint64`. For `uint32` values, mask an `int` with `land 0xFFFF_FFFF`. Literals:
  `0x5851F42D4C957F2DL`. Int64 values are boxed but ocamlopt unboxes them inside a function, so
  keep the generator step in a small function or a `ref` loop.
- **`mod` and `/`** truncate toward zero (like C), so a negative left operand gives a negative
  remainder. Check the spec's definition.
- **Float output.** Print every float as an integer: `Float.to_int (Float.round (x *. 1e9))`.
  `Float.round` rounds half away from zero, as CONVENTIONS asks. Never `%f`/`%g`.
  Float arithmetic needs the dotted operators (`+.`, `*.`, `sqrt`), and `float_of_int` /
  `Float.of_int` for conversions; `float array` is unboxed (flat), records with only float
  fields are unboxed too.
- **Output buffering.** `print_endline` and `print_newline` **flush on every call** (one write
  syscall each). Fine for hello_world and for a few lines; for many lines use
  `print_string`/`Printf.printf "%d\n"` (buffered, flushed at exit) or build a `Buffer.t` and
  print it once. `Printf.printf "%!"` forces a flush. `exit 0` and normal termination flush
  `stdout`.
- **Arguments.** `int_of_string Sys.argv.(1)`. Size 0 must take the same code path.
- **Recursion depth.** OCaml 5 has no C-stack recursion limit: the main fiber's stack grows on
  the heap up to 1 GiB (OCAMLRUNPARAM `l`, which a program must not set). A non-tail recursion
  over a 10-million-element list worked (880 MB RSS); 100 million raised `Stack_overflow`. So
  deep recursion is possible but costs memory: prefer tail recursion with an accumulator, or
  `List.rev` at the end, for anything proportional to the input. `List.map`, `List.init`,
  `List.append`/`@` and `List.concat_map` are tail-recursive since OCaml 5.1 (TRMC);
  `List.fold_right` is not.
- **Strings.** Immutable `string`, mutable `Bytes`. Read a whole file with
  `In_channel.with_open_bin path In_channel.input_all`. `String.split_on_char`,
  `String.lowercase_ascii` exist; there is no whitespace splitter, write one with
  `String.index_from` or a loop.
- **Hashtbl** iterates in an unspecified order: collect to a list and `List.sort` before
  printing. Prefer `Hashtbl.replace` over `Hashtbl.add` (`add` shadows, keeping old bindings).
  For string keys the generic `Hashtbl` is fine; a functor (`Hashtbl.Make`) is ordinary style
  too.
- **Concurrency.** Follow each spec's per-language table. In short: `Domain.spawn` is a real
  parallel OS thread, and the runtime supports only about 128 domains at once (8 recommended on
  this machine). `Thread.create` (library `threads.posix`) gives systhreads that share their
  domain's lock, cheap enough for thousands. `Event.new_channel` gives synchronous (rendezvous)
  channels; `Mutex.protect` and `Condition` exist. ping_pong, spawn_many and prime_sieve each
  say which to use.
- **yojson 3.0** (`Yojson.Safe`). The type is
  `` [ `Null | `Bool of bool | `Int of int | `Intlit of string | `Float of float | `String of string | `Assoc of (string * t) list | `List of t list ] ``.
  3.0 removed the old `` `Tuple `` and `` `Variant `` cases, so a match need not handle them.
  `Yojson.Safe.from_string` / `from_file` parse, `Yojson.Safe.to_string` writes compact JSON
  (`pretty_to_string` is indented), `Yojson.Safe.Util` has `member`, `to_list`, `to_assoc`,
  `to_int`. `` `Assoc `` keeps key order. Integers that do not fit 63 bits become `` `Intlit ``.
  Check its float printing against the spec before relying on it.
- **Warnings** are not errors in the release profile, but keep the code warning-free (dune's
  dev profile turns many into errors; the release one prints them).
