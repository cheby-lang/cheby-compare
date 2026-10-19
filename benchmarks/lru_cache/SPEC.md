# lru_cache

A least-recently-used cache of fixed capacity under a skewed pseudo-random stream of lookups. A hit
moves the key to the most-recent end. A miss inserts the key and evicts the least recent key when
the cache is full. The program prints the hit and miss counts, a sum of the values that hits
returned, and a checksum of the final cache contents in recency order.

## Purpose

- **What it stresses.** A hash lookup on every operation, plus an order update: a move on every hit,
  an insert and often an evict on every miss. At the bench size the cache holds 100 000 entries,
  which is larger than the CPU caches, so memory latency matters too. About 56% of operations hit.
- **Where languages differ.** Languages with a mutable hash map and a doubly linked list (or a
  standard ordered map like Java's `LinkedHashMap`) do one hash probe and a few pointer writes per
  operation. Purely functional languages use persistent maps, where every update copies a path of a
  tree, and the order must be kept by a second persistent structure.
- **Expected for Cheby: a weakness.** Cheby has no mutable state (D-017). Its cache is a
  `std::ordered_map`, which is written in Cheby over a hashed `Map` plus a `SortedMap` from
  insertion number to key (D-336). A hit is `get`, `remove` and `insert`, and each of the last two
  updates both structures. Perceus reference counting lets a uniquely held map be updated in place
  (D-005), which avoids most copying, but each update still walks and rebalances two trees. _Note_:
  a hand-written shape C, with `entries`, `by_tick` and the clock as separate parameters of the
  tail-recursive loop, ran about 12-15% faster than `ordered_map` at 2M operations. Its hit is one
  hash lookup, one overwriting hash insert and two `SortedMap` updates. The `ordered_map` hit is
  `get`, `remove` and `insert`, which do three hash lookups, a hash remove and a fresh hash insert
  in place of the overwrite, plus the same two `SortedMap` updates, because `ordered_map` has no
  move-to-end operation. Keeping both maps in a record and updating it with `..cache` is slower than
  either, because the record keeps the maps shared and they lose in-place reuse unless the record is
  destructured first (D-716). The Cheby program stays on shape A, the first shape that fits.

## Arguments

Two arguments, both decimal integers:

1. `capacity`, the most entries the cache holds. It is at least 1.
2. `ops`, the number of operations. It is at least 0.

## Generator

A Lehmer (Park-Miller "MINSTD") generator. All its values are below 2^31, and every product is below
2^47, so it needs no wrapping arithmetic and is exact in a binary64 double. Use it as written. Never
use a language's own random module.

The state and every product must be 64-bit integers: `long` in Java and C#, `Int` in Swift,
`Int64`/`i64`/`u64` elsewhere, or a double in TypeScript. Never a 32-bit `int` or `i32`: the state
fits, but `state * 48271` reaches about 2^47 and overflows.

```text
LEHMER_M = 2147483647       // 2^31 - 1
LEHMER_A = 48271
SEED     = 42

next(state) = (state * LEHMER_A) mod LEHMER_M      // state stays in 1 .. 2^31 - 2
```

The first state used is `next(SEED)`, not `SEED` itself.

## Key stream

Keys are non-negative integers in `0 .. 16 * capacity - 1`. The first `capacity` keys are the hot
set; the rest are the cold set.

```text
HOT_PERCENT = 80
hot  = capacity
cold = capacity * 15

pick_key(state):
    draw = state div 100                // integer division, state > 0
    if state mod 100 < HOT_PERCENT:
        return draw mod hot             // a hot key, 0 .. capacity-1
    else:
        return hot + draw mod cold      // a cold key, capacity .. 16*capacity-1
```

`div` is integer division. In TypeScript, `state / 100` is a float division, so compute
`draw = Math.floor(state / 100)`; without it `draw % hot` has a fraction and picks wrong keys. `%`
on doubles is exact here, because every operand is a whole number below 2^53.

## Algorithm

```text
MODULUS = 1000000007

cache  = empty           // key -> value, kept in recency order
hits   = 0               // 64-bit integers
misses = 0
values = 0
state  = SEED

repeat ops times:
    state = next(state)
    key   = pick_key(state)
    if cache has key:                       // a hit
        value = cache[key]
        make key the most recently used entry
        hits   = hits + 1
        values = (values + value) mod MODULUS
    else:                                   // a miss
        if size(cache) == capacity:
            remove the least recently used entry
        insert key with value key * 2 + 1 as the most recently used entry
        misses = misses + 1

checksum = 0
position = 1
for each key in cache, from the least recently used to the most recently used:
    checksum = (checksum + position * key) mod MODULUS
    position = position + 1
```

Rules:

- One operation is one lookup. A hit must find the value through the cache, and a miss must insert
  it into the cache. Do not keep a separate "is present" set.
- Only a hit or an insert counts as a use. Evicting does not touch any other entry.
- Evicting before the insert and evicting after it (Java's `removeEldestEntry`) end in the same
  state, because the new key is never present. Either is fine.
- The value is stored in the cache when the key is inserted, and read back from the cache on a hit.
  It is not recomputed from the key on a hit.
- The cache never holds more than `capacity` entries, and it is created empty. You may reserve
  `capacity` slots up front.
- Every intermediate value is below 2^47: generator products are below 2^47, keys are below 2^21 at
  the bench size, and `checksum + position * key` is below 2^38. Plain 64-bit (or 63-bit) integers,
  or doubles in TypeScript, are exact. This includes the generator state, never a 32-bit integer.
- Single-threaded.

## Output

Exactly four lines, each ending in `\n`, one space between the word and the number:

```text
hits <hits>
misses <misses>
values <values>
checksum <checksum>
```

For `capacity = 1000`, `ops = 200000` (the test size):

```text
hits 112201
misses 87799
values 124584795
checksum 366011698
```

## Size 0

`ops = 0` with the bench capacity. The program parses both arguments, creates the empty cache and
prints zeros. The checksum of an empty cache is 0.

```text
hits 0
misses 0
values 0
checksum 0
```

## Sizes

| Size    | `capacity` | `ops`    | Notes                                    |
| ------- | ---------- | -------- | ---------------------------------------- |
| `zero`  | 100000     | 0        | four zero lines                          |
| `test`  | 1000       | 200000   | Python takes about 0.07 s                |
| `bench` | 100000     | 20000000 | Rust about 0.6-0.8 s, Python about 7.5 s |

## Representation

Use the standard library. Choose the first shape below that your language's standard library
supports, and keep the operation count the same: one lookup per operation, then the move, or the
evict and insert.

**A. Ordered or linked hash map.** A hash map that keeps entries in order, where a hit can move a
key to the end in O(1) and the first entry is the least recent.

- **Java**: `LinkedHashMap<Long, Long>(capacity, 0.75f, true)` in access order. `get` moves the key.
  Evict with `removeEldestEntry` returning `size() > capacity`, or with `iterator().next()` and
  `remove` before `put`.
- **Python**: `collections.OrderedDict`. A hit is `get` then `move_to_end(key)`. Evict with
  `popitem(last=False)`.
- **Ruby**: `Hash` keeps insertion order. A hit is `delete(key)` and re-insert. Evict with `shift`.
- **Scala**: `scala.collection.mutable.LinkedHashMap[Long, Long]`. A hit is `remove` and `update`.
  Evict `head`.
- **Cheby**: `std::ordered_map`. A hit is `ordered_map::remove` and `ordered_map::insert`, which
  moves the key to the end (D-340). Evict with `ordered_map::first` and `remove`. The checksum is an
  `ordered_map::fold`. Loops are tail-recursive functions.

**B. Hash map plus a doubly linked list.** The map goes from key to list node. The list goes from
least recent (head) to most recent (tail). A hit unlinks the node and appends it at the tail. An
evict removes the head node and its key from the map, and may reuse that node for the insert.

- **Rust**: `std::collections::HashMap<u64, usize>` with the default hasher, and the list as a `Vec`
  of nodes linked by `usize` index (the idiomatic safe form). No crates.
- **C++**: `std::unordered_map<int64_t, std::list<Entry>::iterator>` plus `std::list<Entry>`, with
  `splice` to move a node to the end.
- **Go**: `map[int]*list.Element` plus `container/list`, with `MoveToBack`.
- **C#**: `Dictionary<long, LinkedListNode<(long Key, long Value)>>` plus `LinkedList<...>`.
- **TypeScript**: `Map<number, number>` from key to slot, plus an index-linked list: `Int32Array`
  for `prev` and `next`, and `number[]` (or `Float64Array`) for keys and values. Use `number`, not
  `bigint`. Not shape A: V8 leaves a hole for each deleted `Map` entry, and every new `keys()`
  iterator skips the holes from the start of the table, so `map.keys().next()` as the evict is O(n)
  under delete/set churn. A shape A program takes over 180 s at the bench size.
- **Swift**: `Dictionary<Int, Int>` from key to slot, plus arrays (or an array of structs) for the
  node fields, linked by index.
- **Zig**: `std.AutoHashMap(u64, u32)` from key to slot plus a node `ArrayList` linked by index, or
  `std.DoublyLinkedList` with nodes from the allocator. Call `index.rehash()` once every `capacity`
  removals (for example, count evicts and rehash when the count reaches `capacity`). Zig's `HashMap`
  leaves a tombstone for each removed key and rehashes only when it grows, which never happens at a
  constant size, so probes lengthen without bound and lookups, misses most of all, degrade to O(n)
  under remove/insert churn. Without the rehash the bench size does not finish in minutes; with it,
  it takes about 2 s. `std.DoublyLinkedList` does not avoid this: the problem is in the hash map,
  not the list.
- **Odin**: `map[int]int` from key to slot plus a `[dynamic]Node` linked by index.
- **Nim**: `Table[int, int]` from key to slot plus a `seq` of nodes linked by index, or `std/lists`.
  Do not use `OrderedTable`: its `del` is O(n).
- **OCaml**: `Hashtbl` from key to a node, and the list as records with `mutable prev` and
  `mutable next` fields. This is ordinary imperative OCaml. A circular list around a sentinel node
  (`let rec sentinel = { ...; prev = sentinel; next = sentinel }`) is fine and avoids `option`
  links, whose `Some` boxes each unlink and append would allocate.

**C. Two persistent maps and a clock.** For languages whose idiomatic style is persistent data and
whose standard library has neither shape above. Every use of a key takes the next tick of a clock
that starts at 0. `entries` maps each key to `(value, tick)`. `by_tick` maps each live tick to its
key. The least recent key is the one with the smallest live tick.

```text
hit:   (value, old) = entries[key]
       by_tick = remove old, then insert clock -> key
       entries = insert key -> (value, clock)
       clock = clock + 1
evict: (t, k) = smallest entry of by_tick
       remove t from by_tick and k from entries
miss:  entries = insert key -> (key * 2 + 1, clock)
       by_tick = insert clock -> key
       clock = clock + 1
checksum: walk by_tick in increasing tick order
```

`by_tick` should be an ordered map with a cheap minimum (a balanced tree). Where the standard
library has only a hash map, keep a counter `oldest`, never larger than a live tick. To evict, count
`oldest` up until `by_tick` has it, evict that tick, and set `oldest` past it. Each tick is skipped
once, so eviction is O(1) amortized. The checksum then walks ticks from `oldest` to `clock - 1`,
skipping the ones not in `by_tick`, or sorts the live `(tick, key)` pairs by tick. The observable
results are the same in every shape; the reference outputs were checked against shapes A, B and C.

- **Erlang**: `entries` a map, `by_tick` a `gb_trees`, evict with `gb_trees:take_smallest`, the
  checksum with `gb_trees:iterator`. Loops are tail-recursive functions.
- **Elixir**: the same, with a `Map` and `:gb_trees`.
- **Gleam**: `gleam/dict` for both maps, with the `oldest` counter. Loops are tail-recursive.
- **Clojure**: `entries` a `hash-map`, `by_tick` a `sorted-map`, evict with `first`. Use
  `loop`/`recur`. Do not drop to `java.util.LinkedHashMap` interop.
- **Koka**: its standard library has no hash map. Write a small persistent map over `int` keys (for
  example a red-black tree, or a hash-array-mapped trie), and use it for both maps; a tree has its
  minimum for the evict. If a fluent Koka programmer would use a mutable `vector`-based hash table
  with local `var`s instead, shape B is also allowed. Say which in `impl.toml` `notes`.
