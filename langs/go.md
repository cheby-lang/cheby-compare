# Go in cheby-compare

Go 1.27.2 from Homebrew (`/opt/homebrew/bin/go`, a symlink to the real binary, not a shim).
The standard library covers every benchmark: `encoding/json` for JSON, goroutines and channels
for concurrency. **No third-party modules** are needed or allowed (CONVENTIONS "Standard library
first": Go has JSON in std).

## Project layout

One module per implementation, in `benchmarks/<bench>/go/`:

```text
benchmarks/<bench>/go/
  go.mod       module main / go 1.27   (exactly these two lines, no go.sum when there are no deps)
  main.go      package main; more .go files of package main may sit next to it
  impl.toml    optional: libs, notes, or overrides of langs/go.toml keys
```

Copy `benchmarks/hello_world/go/go.mod` as is. Start `main.go` with a `//` comment saying what
the program does, and keep it `gofmt`-clean (`gofmt -l .` prints nothing).

## Build, clean, run (langs/go.toml)

- `env`: `GOTOOLCHAIN=local` (never auto-switch toolchains), `GOCACHE={build}/gocache`
  (a cache private to this implementation, `build/go/<bench>/gocache`).
- `build`: `go build -o {build}/main .` — Go's release build, default flags. No `-trimpath`,
  no `-ldflags=-s -w`, no `-gcflags`, no PGO (do not add a `default.pgo` file).
- `clean`: removes `{build}/main` and `{build}/gocache`, refreshes `{build}/gocache.warm` with
  every package outside the main module that the program imports (std and any third-party
  module), and clones it back to `{build}/gocache` with `cp -c` (APFS copy-on-write, ~80 ms). The
  timed build then compiles and links only `package main` (and any packages of module `main`).
  The first clean of a benchmark compiles its std deps once (~2 s); later ones are no-ops.
- `run`: `{build}/main {args}` (the executable). `artifact`: `{build}/main`.

Measured on hello_world: clean→build ≈ 215 ms (compile of main + link), start-up ≈ 1.8 ms. A
cache-hit rebuild is ≈ 45 ms, so a ~200 ms build confirms the clean did its job.

By hand, from the repository root:

```sh
python3 runner/run.py verify -l go -b <bench> --sizes zero,test,bench --diff
python3 runner/run.py build -l go -b <bench>

# or manually, in benchmarks/<bench>/go:
export GOTOOLCHAIN=local GOCACHE=$PWD/../../../build/go/<bench>/gocache
go build -o ../../../build/go/<bench>/main . && ../../../build/go/<bench>/main 10
go vet .
```

## Adding a third-party module (not expected for Go)

Should a library variant ever need one: `cd benchmarks/<bench>/go && go get example.com/m@vX.Y.Z`
(writes `require` to go.mod and go.sum; commit both), list it in `impl.toml` as
`libs = ["example.com/m vX.Y.Z"]`. The module lands in the user's module cache
(`go env GOMODCACHE`), which `clean` never touches; `setup/go.sh` runs `go mod download` for
every `go.mod` that has a `require`, so builds work offline afterwards. `clean` warms the
module's compiled packages along with std, so the timed build still compiles only your code.
No vendoring, no `replace` to local paths.

## Gotchas

- **Integers.** `int` is 64-bit here (darwin/arm64), but write `int64`/`uint64` where the spec
  says 64-bit, so the width is explicit. Unsigned arithmetic wraps silently, which is what the
  LCG/xorshift/FNV generators want: use `uint64` (or `uint32`) for them. Signed overflow also
  wraps (two's complement, no panic). `>>` on a signed value is arithmetic; on unsigned, logical.
  Conversions such as `uint32(x)` truncate.
- **`%` and `/`** truncate toward zero (like C/Rust); a negative left operand gives a negative
  remainder. Check the spec's mod definition.
- **Float output.** Every float prints as an integer: `int64(math.Round(x * 1e9))`.
  `math.Round` rounds half away from zero, exactly as CONVENTIONS asks. Never `%f`/`%g`.
- **Arguments.** `strconv.Atoi(os.Args[1])` (or `ParseInt(..., 10, 64)`). Size 0 must work and
  take the same code path.
- **Output.** `fmt.Println` writes unbuffered to `os.Stdout` (one syscall per call). For more
  than a handful of lines use `w := bufio.NewWriter(os.Stdout); defer w.Flush()` and
  `fmt.Fprintln(w, ...)` / `w.WriteString`. `defer` does not run on `os.Exit`, so return from
  `main` instead. Print with `strconv.AppendInt`/`fmt.Fprintln`; output must end lines with `\n`.
- **Maps** iterate in random order: collect keys, `slices.Sort` / `slices.SortFunc` (with
  `cmp.Compare`) before printing. Use `min`/`max` builtins, `slices`, `maps`, range-over-int
  (`for i := range n`) and range-over-func iterators freely; they are all in 1.27.
- **Recursion.** No recursion limit: goroutine stacks grow on demand up to 1 GB (64-bit), so
  deep recursion (binary_trees, recursive descent) is fine.
- **GC / runtime.** Keep the defaults: no `GOGC`, `GOMEMLIMIT`, `GOMAXPROCS` or
  `debug.SetGCPercent`. The program must read no environment variable.
- **Concurrency.** `go f()` goroutines, unbuffered `make(chan int64)` where the spec says
  unbuffered, `sync.WaitGroup` for joins (`wg.Go(func(){...})` exists since 1.25, or
  `Add`/`Done`). Close channels you range over. Follow each spec's per-language table.
- **JSON** (`encoding/json`, v1). Decode into structs with `json:"name"` tags; struct fields
  marshal in declaration order, while `map[string]any` marshals with **sorted** keys (wrong for
  order-preserving output). A nil slice marshals as `null`: start from `make([]T, 0)`.
  `json.Marshal` escapes `<`, `>`, `&` as `<...` unless you use an `Encoder` with
  `SetEscapeHTML(false)`; and `Encoder.Encode` appends a `\n`. Numbers decoded into `any` become
  `float64`; decode into `int64` fields instead. `encoding/json/v2` exists in 1.27 but the
  spec's guidance names `encoding/json`; stay with v1 unless a spec says otherwise.
- **Strings.** `string(bytes)` copies; `strings.Fields` / `bytes.Fields` split on ASCII and
  Unicode whitespace. Read whole files with `os.ReadFile(path)`.
- **Don't** add `//go:noinline`, `unsafe`, assembly, or build tags.
