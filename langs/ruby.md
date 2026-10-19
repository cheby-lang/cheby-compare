# Ruby (`ruby`) guide for benchmark authors

Toolchain: Ruby 4.0.7 from Homebrew (`/opt/homebrew/opt/ruby/bin/ruby`, +PRISM, YJIT built in),
json 2.18.0 (default gem). Config: `langs/ruby.toml`. Extra setup: `setup/ruby.sh` (idempotent;
it only checks that Ruby 4.0, YJIT and json are there, and installs the `ruby` formula if missing).

## Layout

No project, no manifest, no build step. Each implementation is one file:

```text
benchmarks/<bench>/ruby/
  main.rb     the entry point; start it with a `#` comment saying what it does
  *.rb        more files only if you really need them, loaded with require_relative
  impl.toml   optional: libs, notes, or a key override
```

## What the config does

```text
env   PATH = /opt/homebrew/opt/ruby/bin:$PATH
build = ""          (none: Ruby parses and compiles to bytecode on every run, no bytecode cache)
clean = ""
run   = ruby --yjit main.rb {args}
```

- `/usr/bin/ruby` is macOS's Ruby 2.6 (no YJIT), so the `env` PATH prefix matters. The merge rule
  in run.py: an `env` table in `impl.toml` is merged key by key over the lang's, so if you set
  `PATH` there, keep `/opt/homebrew/opt/ruby/bin:$PATH` in it.
- `--yjit` is the only flag (CONVENTIONS: Ruby runs with YJIT). No `--disable-gems`, no
  `RUBYOPT`, no bootsnap: default start-up, which loads rubygems, did_you_mean and error_highlight.
- With no build, the runner records no compile time; parse and bytecode compile are part of the
  run and start-up times. hello_world start-up is about 31 ms, 18 MB RSS.
- For `compile_large` the runner times `run` with **no arguments** in the generated project, so
  that project's `main.rb` must work with an empty `ARGV`.

## Building and running by hand

From `benchmarks/<bench>/ruby/`:

```sh
/opt/homebrew/opt/ruby/bin/ruby --yjit main.rb 10
```

What counts is the runner:

```sh
python3 runner/run.py verify -l ruby -b <bench> --sizes zero,test,bench --diff
```

Anything written to stderr is fine for verify but should not happen; warnings would show there.

## Third-party dependencies

None are needed, and CONVENTIONS allows none for Ruby: JSON is the `json` default gem
(`require "json"`, C extension), `Set` is core in Ruby 4.0 (no `require "set"` needed), and
`Thread`, `Queue` and `SizedQueue` are core. If one were ever allowed, the recipe would be: install
it in `setup/ruby.sh` with `gem install --install-dir "$ROOT/build/ruby/gems" <gem> -v <version>`
(cached, offline afterwards), set `GEM_PATH = "{root}/build/ruby/gems"` in the impl's `env`, plain
`require` it, and name it in `impl.toml` `libs`. Never run through `bundle exec` (it adds its
own start-up), and never commit the gems.

## Gotchas

- **Integers are arbitrary precision.** There is no wrapping. For a 64-bit LCG or xorshift, mask
  after every step: `x = (x * A + C) & 0xFFFF_FFFF_FFFF_FFFF` (the product is briefly a Bignum,
  which is correct, just slower). Xorshift left shifts also need the mask. If the SPEC wants a
  *signed* 64-bit value, convert: `x >= 2**63 ? x - 2**64 : x`. Values within 62 bits stay
  Fixnums (fast); sums such as ping_pong's need no care.
- **Division and modulo floor**, unlike C/Rust/Java, which truncate: `-7 / 2 == -4`,
  `-7 % 2 == 1`. Use `remainder` for a truncated remainder (`-7.remainder(2) == -1`). With
  non-negative operands, as in the generators, they agree. `/` on two Integers is integer
  division; use `fdiv` or a Float operand for a float result.
- **Float output.** `Float#round` rounds half away from zero by default (`2.5.round == 3`,
  `-2.5.round == -3`), which is exactly the CONVENTIONS rule: print `(x * 10**k).round`. It returns
  an Integer, so it prints without `.0`. Never print a Float directly.
- **Recursion limit**: about 10,000 frames of a simple method (`SystemStackError`), on the main
  thread and in a `Thread` alike (1 MB VM stack each). Tree depths of 20-odd are fine; anything
  that recurses once per element of a list must be a loop. Do not raise the limit with
  `RUBY_THREAD_VM_STACK_SIZE`: the program reads no environment variable and the run command takes
  no extra settings.
- **Threads are OS threads** under the GVL (the M:N scheduler is off by default, and we keep it
  off: no `RUBY_MN_THREADS`). 1,000 threads at once work (macOS allows 4,096 per process); 10,000
  spawn+join with `value` take about 0.3 s. Use what the SPEC tables say: `Thread.new` with
  `thread.value` or `join`, `SizedQueue.new(1)` with `push`/`pop`. No Ractors, no Fiber scheduler
  (no SPEC asks for them).
- **Strings.** Literals are "chilled" in 4.0: mutating one works silently by default but warns
  with `-W:deprecated`. Put `# frozen_string_literal: true` at the top when you build strings, and
  use `+""` or `String.new` for a mutable buffer.
- **Output.** `$stdout` is buffered when it is a pipe, so many `puts` calls are fine; no
  `sync = true`, no explicit flush. `puts` with an Array prints one element per line.
- **JSON** (json_roundtrip): `JSON.parse` gives Hashes that keep key order, Integers (Bignum if
  large) and Floats; `JSON.generate` is compact. Follow the SPEC's number rules, not Ruby's float
  formatting.
- **Idiom.** Small value records: `Struct.new(...)` or a class with `attr_accessor` (SPEC says
  which, e.g. binary_trees: a class with two attributes and `nil`). `Data.define` is immutable,
  fine where nothing is mutated. Hot loops: `while` loops and `Integer#times` are both idiomatic;
  YJIT handles either well. Endless methods (`def f(x) = ...`) and `it` are available.
