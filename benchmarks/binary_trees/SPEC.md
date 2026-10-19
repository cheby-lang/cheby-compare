# binary_trees

The benchmarks-game binary-trees program, single-threaded.

## Purpose

It stresses the allocation and freeing of many small heap nodes, and a recursive walk over them.
Almost all the time goes to the allocator, or to the garbage collector, and to pointer chasing.

- Tracing collectors with bump allocation (JVM, Go, OCaml, BEAM, .NET, V8) usually do well. Most
  trees die young and never leave the nursery.
- Languages that free each node by hand or by reference count pay one free per node. Their speed
  depends on the allocator behind them.
- For Cheby this is a probe of Perceus reference counting (D-005). Every node is uniquely owned,
  so no count ever goes above one, but each node still costs one allocation, one free and the
  count updates. Cheby's runtime has a per-fiber block cache in front of mimalloc (D-890), so it
  should be close to the AOT languages that use their platform's default allocator. It is not
  expected to match the tracing collectors.

## Arguments

One argument: `n`, the maximum depth, a non-negative integer. There is no clamping. In particular
`n` is **not** raised to `min_depth + 2` as in the original benchmarks-game program.

## Data

A tree is made of nodes. A node is a heap-allocated value with two children, `left` and `right`.
Each child is either another node or absent. A node with two absent children is a leaf.

- Absent is the language's normal "no value": `None`, `null`, `nil`, or a nullary constructor such
  as `Empty`.
- In every language, one node is one separate heap allocation (or one boxed value). A tree of depth
  `d` therefore has `2^(d+1) - 1` allocated nodes.
- A leaf the compiler turns into a constant does not count as an allocation and must be avoided.
  The BEAM compilers make `{node, nil, nil}` one shared literal, and OCaml makes
  `Node (Empty, Empty)` a static constant. Every leaf must be a fresh node, built at run time (see
  Per-language guidance).
- No arenas, pools, free lists, custom allocators or preallocated node vectors. Use the language's
  default allocator or garbage collector.
- A node holds no payload. The original program's item field is gone.

## Algorithm

```text
min_depth = 4

make(d):                              # a perfect tree of depth d
  if d == 0: return Node(absent, absent)
  return Node(make(d - 1), make(d - 1))   # left first, then right

check(t):                             # the number of nodes, by walking the tree
  return 1 + (check(t.left) if t.left present else 0)
           + (check(t.right) if t.right present else 0)

main(n):
  stretch_depth = n + 1
  print "stretch tree of depth {stretch_depth}\t check: {check(make(stretch_depth))}"
  # the stretch tree is unreachable from here on

  long_lived = make(n)                # stays alive until the last line

  d = min_depth
  while d <= n:                       # d = 4, 6, 8, ..., up to n; none when n < 4
    iterations = 2^(n - d + min_depth)
    total = 0
    repeat iterations times:
      total = total + check(make(d))  # build one tree, check it, drop it
    print "{iterations}\t trees of depth {d}\t check: {total}"
    d = d + 2

  print "long lived tree of depth {n}\t check: {check(long_lived)}"
```

Rules:

- `check` must walk the tree. It must not compute the count from the depth.
- `check` looks at both children of every node, as in the pseudo-code. No leaf shortcut: it must
  not assume the tree is perfect and return 1 as soon as `left` is absent.
- Each tree is fully built before it is checked. No laziness, no fusion of `make` and `check`, no
  sharing of subtrees: both calls `make(d - 1)` build fresh subtrees.
- Build a new tree on every iteration. Never reuse a tree across iterations.
- The long-lived tree is built after the stretch line is printed and before the loop, and it stays
  reachable until its own line is printed. Its check is computed after the loop.
- Use the language's normal integer type for `iterations` and `total`, as long as it holds at
  least 2^31 exactly: `Int` or `int64` in most languages, the native 63-bit `int` in OCaml, a plain
  `number` in TypeScript (not `BigInt`), and the default integer in Python, Ruby, Erlang, Elixir
  and Clojure. The largest value at `bench` is 8,388,592, and values stay below 2^31 for every `n`
  up to 26, so a wider or boxed type gains nothing.
- Single-threaded: the iterations of a depth are not spread over threads, tasks or processes.

## Output

Exactly these lines, each ending in `\n`. Each `\t` is one tab character, followed by one space.
Integers print in plain decimal.

```text
stretch tree of depth <n+1>\t check: <count>
<iterations>\t trees of depth <d>\t check: <total>      one line per d, in increasing order
long lived tree of depth <n>\t check: <count>
```

For `n = 10`:

```text
stretch tree of depth 11	 check: 4095
1024	 trees of depth 4	 check: 31744
256	 trees of depth 6	 check: 32512
64	 trees of depth 8	 check: 32704
16	 trees of depth 10	 check: 32752
long lived tree of depth 10	 check: 2047
```

## Size 0

`n = 0` runs the whole program with no depth lines: a stretch tree of depth 1 (3 nodes) and a
long-lived tree of depth 0 (1 node).

```text
stretch tree of depth 1	 check: 3
long lived tree of depth 0	 check: 1
```

## Sizes

| Size    | `n` | Notes                                          |
| ------- | --- | ---------------------------------------------- |
| `zero`  | 0   | two lines, no depth loop                       |
| `test`  | 10  | about 136 thousand nodes                       |
| `bench` | 18  | about 68 million nodes; Rust takes about 1 s   |

## Per-language guidance

- **Rust**: `struct Node { left: Option<Box<Node>>, right: Option<Box<Node>> }`, the default global
  allocator. `make` returns `Box<Node>`.
- **C++**: a `struct Node` with two `std::unique_ptr<Node>` children, made with `std::make_unique`.
  Trees are freed by the destructors.
- **Zig**: a `Node` struct with two `?*Node` fields, allocated one by one from
  `std.heap.smp_allocator`, and freed recursively after the check. No `ArenaAllocator`,
  `MemoryPool` or `c_allocator`. Zig has no implicit global allocator, and `smp_allocator` is its
  own general-purpose allocator for release builds, so it is the "default allocator" of this rule,
  as libc `malloc` is for Rust and C++. Naming one keeps the result from depending on the choice.
- **Odin**: a `Node` struct with two `^Node` fields, `new(Node)` from the default
  `context.allocator`, and a recursive `free` after the check. No arena.
- **Nim**: `type Node {.acyclic.} = ref object` with two `Node` fields (`nil` for absent), under
  the default memory manager (ORC). The `{.acyclic.}` pragma is required: it is the usual Nim idiom
  for trees, and it tells ORC not to track the type for cycle collection. Swift's ARC and Cheby's
  reference counting have no cycle collector either.
- **Swift**: `final class Node` with two `Node?` properties. ARC frees the trees.
- **Go**: `type Node struct { left, right *Node }`, `&Node{}`, the default GC settings.
- **Java, Scala, C#**: a class (a reference type, not a struct or value class) with two fields,
  `null` for absent. Scala may use a `final case class Node(left: Node, right: Node)` or an
  `enum Tree { case Empty; case Node(l: Tree, r: Tree) }`.
- **TypeScript**: a class or an object literal `{ left, right }`, `null` for absent.
- **Python, Ruby**: a class with two attributes (Python with `__slots__`), `None`/`nil` for absent.
  A tuple `(left, right)` is also acceptable in Python. Recursion depth is at most `n + 1`.
- **OCaml, Koka, Gleam, Elixir, Erlang**: an algebraic type or tagged tuple, such as
  `type tree = Empty | Node of tree * tree`, `type tree { Empty; Node(l: tree, r: tree) }`, or
  Erlang's `{node, L, R}` with the atom `nil`. Loops become tail-recursive functions that carry
  `total` and the remaining count. Keep the compiler from making the leaf a constant (see Data).
  OCaml binds `let empty = Sys.opaque_identity Empty` and builds leaves as `Node (empty, empty)`.
  Erlang, Elixir and Gleam pass the absent value into `make` as a parameter (`make(d, empty)`,
  called with `nil` or `Empty`), and export `make`, so the compiler cannot fold it back into a
  literal.
- **Clojure**: a `deftype`/`defrecord` with two fields, or a two-element vector `[left right]`, with
  `nil` for absent. Build eagerly; no lazy sequences inside the tree. Use `loop`/`recur` for the
  iterations.
- **Cheby**: `type Tree { Empty, Node(Tree, Tree) }`, recursive helpers for the loops, and `1 << k`
  for the power of two.
