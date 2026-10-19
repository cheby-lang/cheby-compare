# fannkuch_redux

The benchmarks-game fannkuch-redux program, single-threaded.

## Purpose

It walks every permutation of `0..n` in one fixed order. For each permutation it counts how many
prefix reversals ("pancake flips") bring `0` to the front. The work is tiny integer operations on a
small sequence of at most 12 elements: reads, writes, a prefix reversal and a prefix rotation. There
is no allocation in the array languages and almost no memory traffic.

- Languages with mutable arrays and tight loops (Rust, C++, Zig, Odin, Go, Swift, Nim) should do
  best. The whole state fits in a few cache lines.
- JIT runtimes (JVM, CLR, V8) should be close behind once warmed up.
- Languages without mutable arrays (Erlang, Elixir, Gleam, Koka, Clojure) work on an immutable
  sequence. They either rebuild part of a linked list on every flip and rotation, or update a
  persistent indexed sequence one element at a time, so they allocate or copy where the others do
  not. OCaml uses `Array` here (see Representation guidance).
- For Cheby this is a **deliberate weak point**. Cheby has no arrays and no mutation (D-017). Its
  `List` is a persistent RRB vector (D-039). Flips and rotations are index updates with
  `list::get` and `list::set`. `list::set` keeps value semantics, but it updates in place when the
  list is unique (§9.3), so after the first write of a flip (which copies, because `perm1` still
  holds the shared value) the rest of the flip writes in place. Each update still walks the tree
  and checks uniqueness, so expect Cheby well behind the array languages, and near the other
  immutable-sequence languages.

## Arguments

One argument: `N`, the number of elements, an integer with `0 <= N <= 12`.

`N = 0` is the size-0 run. The program then runs the full algorithm below with `n = 1`: one
permutation, `[0]`, with zero flips. It prints `Pfannkuchen(0)`, the argument as given. In every
case, `n = max(N, 1)` and the output names `N`.

## Algorithm

All indexes are 0-based. `perm1`, `perm` and `count` are sequences of `n` integers. `r`, `k`,
`flips`, `checksum`, `max_flips` and `perm_index` are integers.

```text
fannkuch(n):                          # n >= 1
  perm1 = [0, 1, ..., n - 1]
  count = [0, 0, ..., 0]              # n zeros
  max_flips = 0
  checksum = 0
  perm_index = 0                      # how many permutations came before this one
  r = n

  loop:
    # 1. Reset the counters below r.
    while r != 1:
      count[r - 1] = r
      r = r - 1

    # 2. Count the flips of the current permutation, on a copy.
    perm = copy of perm1
    flips = 0
    k = perm[0]
    while k != 0:
      reverse perm[0..k]              # the first k + 1 elements, both ends included
      flips = flips + 1
      k = perm[0]
    max_flips = max(max_flips, flips)
    if perm_index is even: checksum = checksum + flips
    else:                  checksum = checksum - flips

    # 3. Advance perm1 to the next permutation.
    loop:
      if r == n: return (checksum, max_flips)
      # rotate perm1[0..r] left by one: the first element moves to index r
      first = perm1[0]
      for i in 0 .. r - 1: perm1[i] = perm1[i + 1]
      perm1[r] = first
      count[r] = count[r] - 1
      if count[r] > 0: break          # leave the inner loop, keep r
      r = r + 1
    perm_index = perm_index + 1

main(N):
  (checksum, max_flips) = fannkuch(max(N, 1))
  print checksum
  print "Pfannkuchen(" + N + ") = " + max_flips
```

`fannkuch(n)` visits all `n!` permutations exactly once. `perm_index` runs from `0` to `n! - 1`.

Rules:

- Follow the pseudo-code step by step. Same permutation order, same flips, same counter updates.
- Count the flips by doing them. No flip tables, no caching of results between permutations, no
  precomputed answers.
- No shortcuts in step 2. Do not skip permutations whose first element is `0` before the loop
  (the loop already does zero flips there). Do not use the "if `perm1[0] == 0` skip the copy"
  or "flip only up to the last fixed point" tricks of some fast entries. One flip reverses exactly
  the first `k + 1` elements.
- The copy in step 2 is free where `perm1` is immutable: just use the same value.
- Single-threaded. No splitting of the permutation space over threads, tasks or processes.
- Integers: every value fits in 32 bits for `N <= 12` (`checksum` is 3968050 at 12). Use the
  language's normal integer type.

## Representation guidance

The algorithm is the same everywhere. Only the sequence representation changes.

- **Languages with mutable arrays** (Rust, Go, Zig, Odin, C++, Java, C#, Swift, Nim, Python, Ruby,
  TypeScript, Scala, and OCaml's `Array`): use a mutable array or vector of machine integers for
  `perm1`, `perm` and `count`. Allocate them once, before the loop. The copy in step 2 is an
  element copy into the preallocated `perm`. Reverse and rotate in place, with the library call
  (`slice::reverse`, `rotate_left`, `std::reverse`, `std::rotate`) or a plain loop.
  - OCaml, Scala: use `Array`, which is idiomatic for this program.
  - Python: a `list`, with slice assignment for the reversal and rotation, is idiomatic.
- **Languages with no mutable arrays in normal style** (Cheby, Erlang, Elixir, Gleam, Koka,
  Clojure): use the language's immutable sequence. Lists, tuples or persistent vectors are all
  fine. One rule covers all of them: each flip and each rotation may take either of two shapes,
  and the implementer picks the one that is idiomatic and fast for the sequence chosen.
  - **Rebuild shape**, natural for linked lists. A flip is
    `reverse(take(perm, k + 1)) ++ drop(perm, k + 1)`. A rotation is
    `tail(front) ++ [head(front)] ++ back`, where `(front, back)` splits `perm1` at `r + 1`.
  - **Index-update shape**, natural for persistent indexed sequences. A flip swaps `perm[i]` and
    `perm[k - i]` for `i` from `0` while `i < k - i`. A rotation reads `perm1[0]`, sets
    `perm1[i]` to `perm1[i + 1]` for `i` from `0` to `r - 1`, then sets `perm1[r]` to the first
    element. Every update is the language's pure, value-returning update: Cheby `list::get` and
    `list::set` on a `List`, Clojure `nth` and `assoc` on a persistent vector, Koka's `vector`
    updated by index, Erlang `element` and `setelement` on a tuple, Elixir `elem` and
    `put_elem`. An update that is in place only when the value is unshared (Cheby §9.3, Koka's
    reuse analysis) counts as pure: the language keeps value semantics.

  `count` may be a list, tuple or vector updated by index. Loops become tail-recursive functions.
  - Clojure: persistent vectors (`subvec`, `rseq`, `into`, `nth`, `assoc`) or lists are
    idiomatic. Transients and Java arrays are not: they turn the program into the array version.
  - Erlang, Elixir: lists, with `lists:split` / `Enum.split` and `lists:reverse`, or tuples with
    `setelement` / `put_elem`.
  - Gleam's standard library has no indexed sequence, so Gleam uses lists and the rebuild shape.
  - Cheby: the index-update shape on `List`, which measured about 1.6 times faster than the
    rebuild shape for flips at `N = 9`.
- Never encode the whole permutation in one integer, and never use a bit trick in place of the
  sequence.

## Output

Two lines, each ending with `\n`:

```text
<checksum>
Pfannkuchen(<N>) = <max_flips>
```

`<checksum>` may be negative and prints with a leading `-` then. There are no other spaces. There
is no float in the output.

Reference values, `N`: checksum, max flips: 0: 0, 0. 1: 0, 0. 2: -1, 1. 3: 2, 2. 7: 228, 16.
8: 1616, 22. 9: 8629, 30. 10: 73196, 38. 11: 556355, 51. 12: 3968050, 65.

## Sizes

| Size    | `N`  | Permutations | Note                                      |
| ------- | ---- | ------------ | ----------------------------------------- |
| `zero`  | `0`  | 1            | runs the full code path on `[0]`          |
| `test`  | `7`  | 5,040        | every language in well under a second     |
| `bench` | `10` | 3,628,800    | Rust about 0.19 s, Cheby about 5 s        |

Rust lands below the 0.5 to 1 second target on purpose. Each step of `N` multiplies the work by
about `N`, so no `N` falls inside the window: `10` gives Rust about 0.19 s and `11` about 2 to
3 s. At `11` Cheby took about 155 s, over the 120-second timeout, and Python about 49 s, and the
other immutable-sequence languages were at risk too. At `10` every language finishes well inside
the timeout, and hyperfine still measures Rust's 0.19 s to within about 3%.

Size 0 loads every function but runs no flip and no rotation, because `[0]` needs no flips and
step 3 returns at once with `r == n`. Cheby's compile estimate therefore relies on its JIT
compiling every function eagerly before `main` runs. Re-check this when M3 changes the
compilation model (lazy compilation, D-254, or `cheby build`).
