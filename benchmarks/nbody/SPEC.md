# nbody

The n-body simulation of the Computer Language Benchmarks Game: the Sun and the four giant planets
under Newtonian gravity, advanced in fixed time steps. The program prints the total energy of the
system before and after the steps.

## Purpose

- **What it stresses.** Float arithmetic and `sqrt` on a handful of small records, repeated many
  millions of times. There is no input and almost no output. Each step does 10 pair interactions
  and 5 position updates on 5 bodies of 7 floats each.
- **Where languages differ.** Languages with mutable structs in an array do the step in place, in
  registers and cache. Languages with immutable values build new bodies every step, so the cost of
  allocating small records and of float boxing shows.
- **Expected for Cheby: a weakness.** Cheby has no mutation and no array type. A step rebuilds the
  list of five records, and every pair builds two new records. How well the JIT keeps floats
  unboxed and reuses unique records (Cheby spec
  [§9.3 Reuse](../../../cheby/docs/spec/09-memory-model.md#93-reuse), in-place update of unique
  values) decides the result.

## Arguments

One argument: `steps`, a non-negative decimal integer, the number of calls to `advance`.

## Constants

Every value below is an IEEE 754 binary64 float. Write the same significand digits as given. The
exponent may be spelled as the language or its formatter requires (`e+00`, `e00`, `e0`), as long as
the literal parses to the same binary64. Gleam, for one, rejects `e+00` and needs `e00`, and
Python's black formatter rewrites `e+00` to `e00`. Compute the derived values with the expression
shown, in the order shown (left to right), at compile time or at run time: the result is the same.

```text
PI            = 3.141592653589793           (the language's pi constant is the same value)
SOLAR_MASS    = 4.0 * PI * PI               i.e. (4.0 * PI) * PI
DAYS_PER_YEAR = 365.24
DT            = 0.01
```

A body has seven fields: `x, y, z, vx, vy, vz, mass`. The five bodies, in this order (index 0 to
4), are built from the literals below. For a planet, `vx = VX * DAYS_PER_YEAR` (and the same for
`vy`, `vz`) and `mass = MASS * SOLAR_MASS`.

| Index | Body    | X                       | Y                        | Z                        |
| ----- | ------- | ----------------------- | ------------------------ | ------------------------ |
| 0     | Sun     | 0.0                     | 0.0                      | 0.0                      |
| 1     | Jupiter | 4.84143144246472090e+00 | -1.16032004402742839e+00 | -1.03622044471123109e-01 |
| 2     | Saturn  | 8.34336671824457987e+00 | 4.12479856412430479e+00  | -4.03523417114321381e-01 |
| 3     | Uranus  | 1.28943695621391310e+01 | -1.51111514016986312e+01 | -2.23307578892655734e-01 |
| 4     | Neptune | 1.53796971148509165e+01 | -2.59193146099879641e+01 | 1.79258772950371181e-01  |

| Index | VX                       | VY                      | VZ                       | MASS                    |
| ----- | ------------------------ | ----------------------- | ------------------------ | ----------------------- |
| 0     | (vx = 0.0)               | (vy = 0.0)              | (vz = 0.0)               | (mass = SOLAR_MASS)     |
| 1     | 1.66007664274403694e-03  | 7.69901118419740425e-03 | -6.90460016972063023e-05 | 9.54791938424326609e-04 |
| 2     | -2.76742510726862411e-03 | 4.99852801234917238e-03 | 2.30417297573763929e-05  | 2.85885980666130812e-04 |
| 3     | 2.96460137564761618e-03  | 2.37847173959480950e-03 | -2.96589568540237556e-05 | 4.36624404335156298e-05 |
| 4     | 2.68067772490389322e-03  | 1.62824170038242295e-03 | -9.51592254519715870e-05 | 5.15138902046611451e-05 |

The Sun has `vx = vy = vz = 0.0` and `mass = SOLAR_MASS` before `offset_momentum`.

## Algorithm

Every expression is evaluated left to right as written, with the usual precedence: `a * b * c` is
`(a * b) * c`, and `a + b + c` is `(a + b) + c`. `x -= e` means `x = x - e`. `sqrt` is the
correctly rounded IEEE square root. `N = 5`.

```text
offset_momentum(bodies):
  px = 0.0; py = 0.0; pz = 0.0
  for i in 0 .. N-1:                        # all five, the Sun included
    px = px + bodies[i].vx * bodies[i].mass
    py = py + bodies[i].vy * bodies[i].mass
    pz = pz + bodies[i].vz * bodies[i].mass
  bodies[0].vx = -px / SOLAR_MASS           # (-px) / SOLAR_MASS
  bodies[0].vy = -py / SOLAR_MASS
  bodies[0].vz = -pz / SOLAR_MASS

energy(bodies) -> float:
  e = 0.0
  for i in 0 .. N-1:
    b = bodies[i]
    e = e + 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
    for j in i+1 .. N-1:
      dx = b.x - bodies[j].x
      dy = b.y - bodies[j].y
      dz = b.z - bodies[j].z
      e = e - b.mass * bodies[j].mass / sqrt(dx * dx + dy * dy + dz * dz)
  return e

advance(bodies):
  for i in 0 .. N-1:
    for j in i+1 .. N-1:                    # pairs (0,1) (0,2) (0,3) (0,4) (1,2) ... (3,4)
      a = bodies[i]; b = bodies[j]          # current values, including this step's earlier updates
      dx = a.x - b.x
      dy = a.y - b.y
      dz = a.z - b.z
      d2 = dx * dx + dy * dy + dz * dz
      mag = DT / (d2 * sqrt(d2))
      a_mag = a.mass * mag
      b_mag = b.mass * mag
      a.vx = a.vx - dx * b_mag;  a.vy = a.vy - dy * b_mag;  a.vz = a.vz - dz * b_mag
      b.vx = b.vx + dx * a_mag;  b.vy = b.vy + dy * a_mag;  b.vz = b.vz + dz * a_mag
  for i in 0 .. N-1:
    bodies[i].x = bodies[i].x + DT * bodies[i].vx
    bodies[i].y = bodies[i].y + DT * bodies[i].vy
    bodies[i].z = bodies[i].z + DT * bodies[i].vz

main(steps):
  bodies = the five bodies above
  offset_momentum(bodies)
  print scaled(energy(bodies))
  repeat steps times: advance(bodies)       # a loop or a tail call, see below
  print scaled(energy(bodies))
```

What must be the same everywhere:

- **The pair order.** Pairs are visited in the order `(0,1) (0,2) (0,3) (0,4) (1,2) (1,3) (1,4)
  (2,3) (2,4) (3,4)`. Each pair reads both bodies' velocities as left by the earlier pairs of the
  same step. So body `k` receives its velocity changes in that order: first as `b` from the pairs
  `(0,k) … (k-1,k)`, then as `a` from `(k,k+1) … (k,4)`.
- **Positions do not move during the pair loop.** They change only in the second loop, after all
  10 pairs, using the new velocities.
- **Constant stack over `steps`.** The outer loop over `steps` must be a loop or a tail call
  (Clojure `loop`/`recur`, Scala `while` or a `@tailrec` function). Nothing may grow with `steps`:
  no non-tail recursion, no lazy sequence that is held on to.
- **The expressions.** Use `mag`, `a_mag` and `b_mag` exactly as above. Do not precompute
  `dx * b.mass`, `1/sqrt`, `mass * DT` or anything else across steps, and do not reorder sums.

`scaled(e)` is `round(e * 1.0e9)` as an integer, rounding half away from zero. `1.0e9` is the
float `1000000000.0`. Use the language's half-away-from-zero rounding (`f64::round`, C's `lround`,
Cheby's `float::round`) where it has one. Where it does not, use a recipe such as
`t = trunc(x); if abs(x - t) >= 0.5 then t = t + sign(x)`. This recipe is the normative rule.

At the chosen sizes every unrounded `e * 1.0e9` is far from a half, so any round-to-nearest mode
(half-up, half-to-even, half-away) prints the expected output. Measured with clang `-O2` under
`-ffp-contract=off`, `on`, and with explicit `fma()` on every `a * b + c`:

| Size    | `e * 1.0e9` after the steps                   | Distance from a half |
| ------- | --------------------------------------------- | -------------------- |
| `zero`  | -169075163.8285 (also the first line, always) | 0.33                 |
| `test`  | -169016441.2644                               | 0.24                 |
| `bench` | -169074991.9714 (off), .9644 (on, fma)        | 0.46                 |

So these built-ins also give the right output here, though they are not half-away-from-zero:
Java's `Math.round` and JavaScript/TypeScript's `Math.round` (halves toward +infinity), Koka's
`round`, Python's `round` and .NET's `Math.Round` (halves to even). If a size changes, recheck the
table before relying on that.

## Representation

The algorithm fixes the arithmetic, not the data structure. Use the language's natural form:

- **Mutable structs in an array** where the language has them: Rust, Go, Zig, Odin, C++, Java, C#,
  Swift, Nim, TypeScript (class instances in an array), Python and Ruby (objects with
  `__slots__`/attributes in a list), Scala (a class with `var` fields in an `Array`).
- **Immutable records in a list, rebuilt every step** where the language has no mutation or
  prefers persistence: Cheby, Gleam, Erlang, Elixir, Koka, OCaml (records in a list, or mutable
  record fields if that is how the developer would write it), Clojure (maps or records in a vector,
  or a `deftype` with mutable fields if that is idiomatic for numeric code). A recursive shape that
  works: take the first body, fold it against each later body (updating both), recurse on the
  updated rest, then prepend the updated first body. This visits the pairs in the required order.
- A precomputed list of the 10 index pairs (or body-reference pairs), built once before the loop,
  is fine.
- **Not allowed:** hand-unrolling the 10 pairs into straight-line code, or keeping the five bodies
  as five separate named variables. The bodies live in one collection and the pair loop iterates
  over it, as in every language.
- Floats are binary64 everywhere. No `f32`, no `long double`, no decimal types.

**Compiler flags.** Do not enable fast-math (`-ffast-math`, `-Ofast`, `@setFloatMode(.optimized)`,
`-funsafe-math-optimizations`, or any relaxed float mode). Fused multiply-add contraction that the
language does by default (clang's `-ffp-contract=on`, Go on arm64) is allowed. It changes the last
bits of the energy but not the printed result at the sizes below: the expected outputs were checked
with clang `-O2` under `-ffp-contract=off`, `on`, and with explicit `fma()` on every `a * b + c` (as
Go may fuse), and every chosen size has its scaled energy at least 0.2 away from a rounding boundary
(the table under Algorithm). Do not write `fma(...)` calls by hand.

## Output

Two lines, each a decimal integer with a leading `-` when negative, and a final newline:

```text
<scaled energy after offset_momentum>
<scaled energy after `steps` calls to advance>
```

For example, with `steps = 1000`:

```text
-169075164
-169087605
```

## Size 0

`steps = 0` runs `offset_momentum`, `energy` twice and no `advance`. It prints `-169075164` twice.
`advance` must still be part of the program (not compiled away by a special case for 0).

## Sizes

| Size    | `steps`  | Output (second line) | Rust, Apple M-series |
| ------- | -------- | -------------------- | -------------------- |
| `zero`  | 0        | -169075164           | ~1 ms                |
| `test`  | 10000    | -169016441           | ~1 ms                |
| `bench` | 22000000 | -169074992           | ~0.55 s              |

The exact outputs are in `expected/`. At `bench`, CPython 3.15 and Cheby (JIT, list of records)
take roughly 55 to 70 seconds (measured with other benchmarks running). The bench size was lowered
from 28M to keep the slowest runtimes clear of the 120-second timeout. A runtime slower than those
two may still time out.
