# spectral_norm

The benchmarks-game spectral-norm program, single-threaded. It estimates the largest singular
value of an infinite matrix, cut to n by n, with 10 rounds of the power method.

## Purpose

The program stresses floating-point arithmetic over vectors. Each step is O(n²): for every output
element it walks the whole input vector, computes one matrix entry with integer arithmetic, converts
it to a float, divides and accumulates. The inner loop allocates only where floats are boxed:
accumulators and returned floats on the BEAM, in Cheby and in Clojure. Walking a list front to back
allocates nothing.

What it shows:

- How fast a tight numeric inner loop runs: integer multiply, int-to-float conversion, float
  division, multiply-add.
- How fast a vector can be walked front to back: an array index in most languages, a list traversal
  in the functional ones.
- The cost of building a fresh vector of n floats 40 times.

**Expected for Cheby: a weakness.** Cheby has no array type. Vectors are `List<Float>`, a persistent
RRB-tree, so each element read goes through a list pattern instead of a load from memory. A `Float`
in a list is a boxed heap object (D-521), and so is a `Float` returned from a function (D-453), so a
small helper like `A(i, j)` allocates on every call unless the JIT inlines it. The Cheby version
therefore writes the formula out in its two inner loops (see its `impl.toml`). Gleam, Erlang,
Elixir and Koka walk lists in the same shape, so they are the closest comparison. They are not
equally slow, though: a plain Erlang list version runs `n = 1000` in about 0.4 s, VM start-up
included, against about 1.2 s for Cheby. That points at float boxing and the `float::from_int` call
rather than at the list itself.

## Arguments

One argument, `n`, a decimal integer with `n >= 0`. It is the length of the vectors and the size of
the matrix.

## Algorithm

The matrix entry, with `i` and `j` counted from 0:

```text
A(i, j) = 1.0 / float((i + j) * (i + j + 1) / 2 + i + 1)
```

The denominator is computed in integers. `(i + j) * (i + j + 1)` is always even, so `/ 2` is exact.
The intermediate product `(i + j)(i + j + 1)` is below 4·n², about 1.21·10⁸ at the bench size, and
the denominator below 2·n², so 32-bit signed integers are enough (up to n ≈ 23000). Computing the same formula in doubles gives the identical value, because every intermediate
is an integer below 2⁵³. Either is allowed, but integers are the expected form.

The program, in pseudo-code:

```text
times_a(x):      # A times x
  n = length(x)
  return [ sum_row(i, x) for i in 0 .. n-1 ]
sum_row(i, x):
  s = 0.0
  for j in 0 .. n-1:        # in this order
    s = s + A(i, j) * x[j]
  return s

times_at(x):     # A transposed times x
  n = length(x)
  return [ sum_col(i, x) for i in 0 .. n-1 ]
sum_col(i, x):
  s = 0.0
  for j in 0 .. n-1:        # in this order
    s = s + A(j, i) * x[j]  # note: A(j, i), indices swapped
  return s

times_ata(x) = times_at(times_a(x))

main:
  u = [1.0] * n
  repeat 10 times:
    v = times_ata(u)
    u = times_ata(v)
  vBv = 0.0; vv = 0.0
  for i in 0 .. n-1:        # in this order
    vBv = vBv + u[i] * v[i]
    vv  = vv  + v[i] * v[i]
  if vv == 0.0: result = 0
  else:         result = round_half_away_from_zero(sqrt(vBv / vv) * 10^9)
  print result
```

Rules that keep the computation the same everywhere:

- Every output element is a dot product over all of `x`, summed from `j = 0` up to `j = n - 1`,
  starting from `0.0`, one term at a time. No other summation order, no pairwise or Kahan summation,
  no several partial accumulators. Do not use Python's built-in `sum()` or `math.fsum` on floats
  (compensated since 3.12), or Java's `DoubleStream.sum()` or `Collectors.summingDouble` (Kahan).
  Use an explicit loop or a plain fold or reduce.
- Compute `A(i, j)` every time it is needed. Writing the formula out in the inner loop or calling a
  helper function are both allowed. Do not store the matrix or a row of it, and do not
  reuse entries between `times_a` and `times_at` or between rounds.
- Use `1.0 / d`. Do not precompute reciprocals.
- `times_ata` is always `times_at` applied to the result of `times_a`. Do not fuse them into one
  pass.
- Exactly 10 rounds, so `times_ata` runs 20 times: 40 matrix-vector products in all.
- Do not call a fused multiply-add explicitly. If the compiler contracts `s + a * b` by default, that
  is fine: the output is the same with and without contraction at every size below. The `go` and
  `cpp` rows keep their compilers' default contraction (Go fuses into `FMADDD` on arm64, clang
  builds with `-ffp-contract=on`). The fused multiply-add then sits on the loop-carried chain, which
  explains most of their gap to Rust and Zig.
- `sqrt` is the language's standard, correctly rounded square root.
- Single-threaded. No SIMD intrinsics.

### Sequential formulation for list languages

The pseudo-code reads `x[j]` in increasing `j`, so it never needs random access. A language with
immutable lists does the same work like this:

```text
times_a(x)  = map (fun i -> fold_left (fun (s, j) xj -> (s + A(i, j) * xj, j + 1)) (0.0, 0) x |> fst)
                  [0 .. n-1]
times_at(x) = the same with A(j, i)
```

The fold carries the running sum and the index `j` of the current element. A tail-recursive walk
over the list with `sum` and `j` as parameters is equally fine. The final dot products zip `u` and
`v`, or walk both lists together, in increasing `i`. `n` is the length of the input list, and the
index list `[0 .. n-1]` may be built once per call or once per program.

## Output

One line: the result as a plain decimal integer, then `\n`. For example `1274224153`.

`round_half_away_from_zero(x)` rounds to the nearest integer and takes halfway cases away from zero.
The value is always positive here. At every listed size the scaled value is at least 0.05 from a .5
boundary, so any round-to-nearest mode and any FMA or contraction setting give the same output.
Half-away-from-zero is still the specified rule.

## Size 0

With `n = 0` the vectors are empty. The program still runs the 10 rounds over empty vectors, `vv`
is `0.0`, and it prints `0`. Never compute `0.0 / 0.0` and round the NaN.

## Sizes

| Size    | `n`  | Output       |
| ------- | ---- | ------------ |
| `zero`  | 0    | `0`          |
| `test`  | 100  | `1274219991` |
| `bench` | 5500 | `1274224153` |

Other values, for checking: `n = 1` prints `1000000000`, `n = 2` prints `1183350177`, `n = 10`
prints `1271844019`, `n = 1000` prints `1274224148`.

The bench size is the benchmarks game's own `n = 5500`. Rust takes about 0.9 s there.

The slowest implementations take about a minute, well inside the 300 s timeout. CPython is
expected at about 75 s and Cheby at about 45 to 50 s.

## Representation, per language

- **Arrays**, where the language has them: Rust `Vec<f64>`, Go `[]float64`, Zig and Odin slices of
  `f64`, C++ `std::vector<double>`, Java and C# `double[]`, Scala `Array[Double]`, Swift `[Double]`,
  Nim `seq[float]`, OCaml `float array` with `for` loops, TypeScript `Float64Array`, Python `list` of
  `float`, Ruby `Array`. Loops are plain `for` loops. Reusing preallocated output and scratch arrays
  across rounds is allowed and expected.
- **Immutable lists** in Cheby (`List<Float>`), Gleam, Erlang, Elixir and Koka, with the sequential
  formulation above. Each `times_a` and `times_at` builds a new list. Koka has `vector<a>` with O(1)
  indexing, but its idiomatic default collection is the list, and the list keeps it comparable with
  Cheby's `List`.
- **Clojure**: persistent vectors, with `reduce-kv` over the input vector, which passes the index
  without a tuple accumulator, and `mapv` over the indices. Primitive hints (`^double`, `^long`) on
  the inner function are fine. Do not switch to Java `double[]` with `aget`/`aset`: the persistent
  vector is Clojure's idiomatic default collection, kept for comparison with Cheby's `List`.
- Integers: use the language's normal integer type (`usize`, `int`, `i64`, `long`). In TypeScript
  use plain numbers. int32 operations such as `>>> 1` and `| 0` are allowed for the integer
  arithmetic of the denominator. They are the nearest JavaScript analogue of the integer arithmetic
  every other language uses.
