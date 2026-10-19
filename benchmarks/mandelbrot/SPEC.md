# mandelbrot

Escape-time iteration of the Mandelbrot set on an `N × N` grid over `[-1.5, 0.5] × [-1, 1]`, at
most 50 iterations per point. The program prints how many points are inside the set, the total
number of iterations, and a checksum of where the inside points are.

## Purpose

- **What it stresses.** A tight loop of float multiplies, adds and one compare, with a counter. No
  allocation, no data structure, no input. At the bench size there are 16 million points and about
  390 million iterations.
- **Where languages differ.** Compiled languages keep `zr`, `zi`, `cr`, `ci` in float registers.
  Dynamic languages and some functional runtimes box each float result, so every iteration
  allocates. Languages without loops express the three loops as tail-recursive functions, so the
  cost of a tail call with float arguments shows.
- **Expected for Cheby: a weakness today.** The algorithm allocates nothing, but the current JIT
  boxes a `Float` at some call boundaries: the result of `float::from_int`, a `Float` returned from
  a call that is not a tail call, and every `Float` passed through a local-function call (D-453
  returns every result as one uniform word). Only the self tail calls of top-level functions keep
  floats unboxed, so the inner loop stays unboxed. Cheby writes the loops as top-level
  tail-recursive functions (see the Cheby note below). It computes `cr` inline in the column loop
  and carries the three totals as accumulator arguments, so no `Float` is returned from a non-tail
  call and no record is built per point. That leaves 1 allocation per point, the result of
  `float::from_int`, about 16 million at the bench size. With 3 per point, a profile put about 20%
  of the samples in boxing and freeing, and the version with a `cr` helper and a record per point
  was about 15% slower.

## Arguments

One argument: `N`, a non-negative decimal integer, the side of the grid.

## Algorithm

All floats are IEEE 754 binary64. Every expression is evaluated left to right as written, with the
usual precedence, each operation rounded to binary64. `2.0 * x / N` means `(2.0 * x) / N`.

```text
MAX_ITER = 50

inside     = 0          // 64-bit integers
iterations = 0
checksum   = 0

for y in 0 .. N-1:                          // rows, in this order
    ci = 2.0 * float(y) / float(N) - 1.0    // once per row
    for x in 0 .. N-1:                      // columns, in this order
        cr = 2.0 * float(x) / float(N) - 1.5
        zr = 0.0
        zi = 0.0
        i  = 0
        while i < MAX_ITER:
            zr2 = zr * zr
            zi2 = zi * zi
            if zr2 + zi2 > 4.0: break
            zi  = 2.0 * zr * zi + ci        // (2.0 * zr) * zi, then + ci
            zr  = zr2 - zi2 + cr            // (zr2 - zi2), then + cr
            i   = i + 1
        iterations = iterations + i
        if i == MAX_ITER:
            inside   = inside + 1
            checksum = checksum + (y * N + x)

print "inside "     + decimal(inside)
print "iterations " + decimal(iterations)
print "checksum "   + decimal(checksum mod 2^32)
```

Rules that keep the bits the same:

- `zi` is updated with the **old** `zr`. Compute `zi` before `zr`, or keep both old values.
- Compute `cr` and `ci` exactly as written: convert the index to float, multiply by `2.0`, divide by
  `float(N)`, subtract. `float(N)` may be computed once and reused, since the conversion is exact.
  Do not precompute `2.0 / N` or `1.0 / N` and multiply: that rounds differently. Do not precompute
  a table of `cr` values.
- The escape test is `zr2 + zi2 > 4.0`, strictly greater, on the squares computed in this
  iteration. It runs before the update, so a point that has escaped is never iterated again. No
  value ever exceeds about 40 in magnitude, so nothing overflows.
- A point that has not escaped after 50 updates counts as inside, whatever its last `z`.
- No shortcuts: no cardioid or bulb test, no periodicity check, no symmetry (the grid is not
  symmetric anyway), no early exit from the grid.
- **IEEE semantics, no fused multiply-add.** No fast-math, no `-ffast-math`, no
  `-Ofast`. Where the compiler would fuse `a * b + c` into an FMA, turn contraction off:
  `-ffp-contract=off` for C, C++ and anything compiled through C (Nim, Koka), explicit
  `float64(...)` conversions in Go, and a bound product in OCaml (below).
- `checksum` is at most `N^4`, below `2^53` for `N <= 9000`, so a 64-bit integer or a JS number
  holds it exactly. Reduce it modulo `2^32` only when printing. `iterations` is at most `50 * N^2`.

### About FMA

Apple clang 21 at `-O2` fuses `2.0 * zr * zi + ci` into one `fmadd` by default, and with
`-ffp-contract=fast` it fuses the escape test too. All three builds (default, `off`, `fast`) gave
the same output for every `N` from 1 to 400 and for 1000, 1500, 2000, 2500, 3000, 4000, 4096, 5000,
6000 and 8000. So 50 iterations are short enough that a one-ulp difference does not move a point
across the escape boundary at these sizes. Do not rely on that: the rule above is normative.

## Output

Exactly three lines, each ending in `\n`, nothing else:

```text
inside 15909
iterations 976575
checksum 320080280
```

That is the output for `N = 200`. The integers are plain decimal with no separators or sign.

## Size 0

`N = 0` prints `inside 0`, `iterations 0` and `checksum 0`. No point is visited. It must not raise:
in languages where float division by zero raises (Erlang, Elixir), compute `ci` inside the row
loop, so it is never computed when there are no rows. Computing it once anyway (as
`0.0 / 0.0 = NaN`) is fine where that does not raise.

Small values to check against:

| N   | inside | iterations | checksum  |
| --- | ------ | ---------- | --------- |
| 1   | 0      | 2          | 0         |
| 2   | 2      | 106        | 5         |
| 10  | 45     | 2553       | 2510      |
| 200 | 15909  | 976575     | 320080280 |

## Sizes

| Size  | N    | Rust (M-series, -O release) |
| ----- | ---- | --------------------------- |
| zero  | 0    | instant                     |
| test  | 200  | about 10 ms                 |
| bench | 4000 | about 0.7 s                 |

Bench output:

```text
inside 6358035
iterations 390512934
checksum 1450096728
```

## Per-language guidance

- **Loops.** Use the language's loops where it has them. Languages without loops (Cheby, Erlang,
  Elixir, Gleam, Koka) write each loop as a tail-recursive function, carrying `zr`, `zi`, `i`
  (inner loop), `x` (columns) and `y` (rows). Clojure uses `loop`/`recur`. OCaml may use
  `for`/`while` with `ref`s or tail recursion, whichever a fluent writer would pick. The three
  totals may be accumulator arguments, a small record or a tuple.
- **Inner loop shape.** A separate function `escape_time(cr, ci) -> i` is fine and expected. It
  must do exactly the iterations above. Inlining it by hand is also fine.
- **Floats.** Use the language's binary64 type: `f64`, `double`, `float64`, `Float`, Python
  `float`, Ruby `Float`, JS `number`. Never a decimal or rational type. Clojure: use primitive
  `double` math (`(double ...)` hints, `loop`/`recur` with unboxed locals) the way a fluent writer
  would; `(/ (* 2.0 x) n)` with a long `n` gives a double. Erlang/Elixir/Gleam: `/` (or `/.`) is
  float division; convert indices with `float/1` / `int.to_float`.
- **Integers.** `inside`, `iterations` and `checksum` need a 64-bit or arbitrary-precision
  integer: `checksum` reaches about 1.45e14 at the bench size, far above `2^31`. Use `long` in Java,
  Scala and C#, `int64_t` or `long long` in C++, `i64` or `u64` in Rust, Zig and Odin, `Int` in
  Swift, `int` in Go and Nim (64-bit), and the plain integers of Koka, Python, Ruby, the BEAM
  languages and Clojure. OCaml's 63-bit `int` is enough. A 32-bit `int` overflows: it wraps in Java
  and C#, and is undefined behaviour in C++. No wrapping is needed at 64 bits.
- **Go.** Go may fuse `x*y + z` into an FMA on arm64, possibly across statements (Go spec,
  "Arithmetic operators", floating-point), so `zr2 + zi2` and `zr2 - zi2` fuse with the squares
  too. Wrap all three products in an explicit conversion, which forbids fusion:
  `zr2 := float64(zr * zr)`, `zi2 := float64(zi * zi)` and `zi = float64(2.0*zr*zi) + ci`. With
  only the `zi` update wrapped, Go 1.27 on arm64 still emits two fused operations.
- **C++.** Build with the flags in `langs/cpp.toml` plus `-ffp-contract=off` in `impl.toml`.
- **Nim, Koka.** They compile through C with clang. Pass `-ffp-contract=off` to the C compiler
  (`--passC:-ffp-contract=off` for Nim; Koka's `--ccopts=-ffp-contract=off`).
- **OCaml.** On arm64, `ocamlopt` (5.5, without flambda) fuses `a *. b +. c` into `fmadd`, and no
  flag turns that off. Bind the product first: `let t = 2.0 *. zr *. zi in ... (t +. ci)`, which
  gives no `fmadd`. `Sys.opaque_identity` on the product is the more robust alternative.
- **Rust, Zig, Swift, Odin, Java, Scala, Clojure, C#, JS, Python, Ruby, BEAM.** They do not
  contract by default. Do not opt in (`mul_add`, `Math.fma`, `@mulAdd`, `FusedMultiplyAdd`).
- **Parallelism.** Single-threaded. No SIMD intrinsics; auto-vectorisation by the compiler is fine.
- **Cheby.** Write the loops as top-level functions. The current JIT boxes a `Float` on every
  local-function call, on every non-tail call that returns a `Float`, and on the result of std
  externals such as `float::from_int`. Only self tail calls of top-level functions keep floats
  unboxed. A version with local `fn` loops measured 14.4 s at the bench size against 3.3 s for
  top-level loops (`Int`-only local loops lose about 25%). That cost is worth measuring separately,
  and it is not the subject of this benchmark, so the Cheby code steers away from local loops,
  the style the Cheby guide otherwise recommends. Compute `float(N)` once and pass it down, as the
  other languages do, which saves a boxed `Float` per point. The same shapes matter for `nbody` and
  `spectral_norm`.
