// lru_cache: an LRU cache as two persistent red-black trees and a clock, under a skewed key stream.

import std/os/env

// ---------------------------------------------------------------------------------------------
// A persistent red-black tree with `int` keys. Koka updates unshared nodes in place (FBIP).

type color
  Red
  Black

type tree<a>
  Node(color : color, left : tree<a>, key : int, value : a, right : tree<a>)
  Leaf

fun lookup(t : tree<a>, k : int) : maybe<a>
  match t
    Node(_, l, kx, v, r) ->
      if k < kx then lookup(l, k)
      elif k > kx then lookup(r, k)
      else Just(v)
    Leaf -> Nothing

// The entry with the smallest key.
fun minimum(t : tree<a>) : maybe<(int, a)>
  match t
    Node(_, Leaf, k, v, _) -> Just((k, v))
    Node(_, l, _, _, _) -> minimum(l)
    Leaf -> Nothing

// Insertion, as in Koka's samples/basic/rbtree-fbip.kk: walk down building a zipper, then
// rebuild and rebalance upwards. An existing key gets the new value.
type zipper<a>
  NodeR(color : color, left : tree<a>, key : int, value : a, up : zipper<a>)
  NodeL(color : color, up : zipper<a>, key : int, value : a, right : tree<a>)
  Done

fip fun move-up(z : zipper<a>, t : tree<a>) : tree<a>
  match z
    NodeR(c, l, k, v, up) -> up.move-up(Node(c, l, k, v, t))
    NodeL(c, up, k, v, r) -> up.move-up(Node(c, t, k, v, r))
    Done -> t

fip(1) fun balance-red(z : zipper<a>, l : tree<a>, k : int, v : a, r : tree<a>) : tree<a>
  match z
    NodeR(Black, l1, k1, v1, z1) -> z1.move-up(Node(Black, l1, k1, v1, Node(Red, l, k, v, r)))
    NodeL(Black, z1, k1, v1, r1) -> z1.move-up(Node(Black, Node(Red, l, k, v, r), k1, v1, r1))
    NodeR(Red, l1, k1, v1, z1) -> match z1
      NodeR(_, l2, k2, v2, z2) -> z2.balance-red(Node(Black, l2, k2, v2, l1), k1, v1, Node(Black, l, k, v, r))
      NodeL(_, z2, k2, v2, r2) -> z2.balance-red(Node(Black, l1, k1, v1, l), k, v, Node(Black, r, k2, v2, r2))
      Done -> Node(Black, l1, k1, v1, Node(Red, l, k, v, r))
    NodeL(Red, z1, k1, v1, r1) -> match z1
      NodeR(_, l2, k2, v2, z2) -> z2.balance-red(Node(Black, l2, k2, v2, l), k, v, Node(Black, r, k1, v1, r1))
      NodeL(_, z2, k2, v2, r2) -> z2.balance-red(Node(Black, l, k, v, r), k1, v1, Node(Black, r1, k2, v2, r2))
      Done -> Node(Black, Node(Red, l, k, v, r), k1, v1, r1)
    Done -> Node(Black, l, k, v, r)

fun ins(t : tree<a>, k : int, v : a, z : zipper<a>) : tree<a>
  match t
    Node(c, l, kx, vx, r) ->
      if k < kx then ins(l, k, v, NodeL(c, z, kx, vx, r))
      elif k > kx then ins(r, k, v, NodeR(c, l, kx, vx, z))
      else z.move-up(Node(c, l, kx, v, r))
    Leaf -> z.balance-red(Leaf, k, v, Leaf)

fun insert(t : tree<a>, k : int, v : a) : tree<a>
  ins(t, k, v, Done)

// Deletion of a key that is present, after Stefan Kahrs, "Red-black trees with types" (2001).

fun balance(l : tree<a>, k : int, v : a, r : tree<a>) : tree<a>
  match l
    Node(Red, la, lk, lv, lb) -> match r
      Node(Red, ra, rk, rv, rb) -> Node(Red, Node(Black, la, lk, lv, lb), k, v, Node(Black, ra, rk, rv, rb))
      _ -> match la
        Node(Red, a, xk, xv, b) -> Node(Red, Node(Black, a, xk, xv, b), lk, lv, Node(Black, lb, k, v, r))
        _ -> match lb
          Node(Red, b, yk, yv, c) -> Node(Red, Node(Black, la, lk, lv, b), yk, yv, Node(Black, c, k, v, r))
          _ -> Node(Black, l, k, v, r)
    _ -> match r
      Node(Red, ra, rk, rv, rb) -> match ra
        Node(Red, b, yk, yv, c) -> Node(Red, Node(Black, l, k, v, b), yk, yv, Node(Black, c, rk, rv, rb))
        _ -> match rb
          Node(Red, c, zk, zv, d) -> Node(Red, Node(Black, l, k, v, ra), rk, rv, Node(Black, c, zk, zv, d))
          _ -> Node(Black, l, k, v, r)
      _ -> Node(Black, l, k, v, r)

// Turns a black node red; only ever called on black nodes.
fun redden(t : tree<a>) : tree<a>
  match t
    Node(Black, a, k, v, b) -> Node(Red, a, k, v, b)
    _ -> t

// Rebalances after the left subtree lost one black level.
fun bal-left(l : tree<a>, k : int, v : a, r : tree<a>) : tree<a>
  match l
    Node(Red, a, xk, xv, b) -> Node(Red, Node(Black, a, xk, xv, b), k, v, r)
    _ -> match r
      Node(Black, a, yk, yv, b) -> balance(l, k, v, Node(Red, a, yk, yv, b))
      Node(Red, Node(Black, a, yk, yv, b), zk, zv, c) ->
        Node(Red, Node(Black, l, k, v, a), yk, yv, balance(b, zk, zv, redden(c)))
      _ -> Node(Black, l, k, v, r)   // unreachable in a valid tree

// Rebalances after the right subtree lost one black level.
fun bal-right(l : tree<a>, k : int, v : a, r : tree<a>) : tree<a>
  match r
    Node(Red, b, yk, yv, c) -> Node(Red, l, k, v, Node(Black, b, yk, yv, c))
    _ -> match l
      Node(Black, a, xk, xv, b) -> balance(Node(Red, a, xk, xv, b), k, v, r)
      Node(Red, a, xk, xv, Node(Black, b, yk, yv, c)) ->
        Node(Red, balance(redden(a), xk, xv, b), yk, yv, Node(Black, c, k, v, r))
      _ -> Node(Black, l, k, v, r)   // unreachable in a valid tree

// Joins two subtrees whose keys are all smaller on the left.
fun fuse(l : tree<a>, r : tree<a>) : div tree<a>
  match l
    Leaf -> r
    Node(lc, a, xk, xv, b) -> match r
      Leaf -> l
      Node(rc, c, yk, yv, d) -> match lc
        Black -> match rc
          Red -> Node(Red, fuse(l, c), yk, yv, d)
          Black -> match fuse(b, c)
            Node(Red, b2, zk, zv, c2) -> Node(Red, Node(Black, a, xk, xv, b2), zk, zv, Node(Black, c2, yk, yv, d))
            bc -> bal-left(a, xk, xv, Node(Black, bc, yk, yv, d))
        Red -> match rc
          Black -> Node(Red, a, xk, xv, fuse(b, r))
          Red -> match fuse(b, c)
            Node(Red, b2, zk, zv, c2) -> Node(Red, Node(Red, a, xk, xv, b2), zk, zv, Node(Red, c2, yk, yv, d))
            bc -> Node(Red, a, xk, xv, Node(Red, bc, yk, yv, d))

fun del(t : tree<a>, k : int) : div tree<a>
  match t
    Leaf -> Leaf
    Node(_, a, yk, yv, b) ->
      if k < yk then
        match a
          Node(Black, _, _, _, _) -> bal-left(del(a, k), yk, yv, b)
          _ -> Node(Red, del(a, k), yk, yv, b)
      elif k > yk then
        match b
          Node(Black, _, _, _, _) -> bal-right(a, yk, yv, del(b, k))
          _ -> Node(Red, a, yk, yv, del(b, k))
      else fuse(a, b)

fun remove(t : tree<a>, k : int) : div tree<a>
  match del(t, k)
    Node(_, a, yk, yv, b) -> Node(Black, a, yk, yv, b)
    Leaf -> Leaf

// In increasing key order.
fun fold(t : tree<a>, acc : b, f : (int, a, b) -> e b) : e b
  match t
    Node(_, l, k, v, r) -> fold(r, f(k, v, fold(l, acc, f)), f)
    Leaf -> acc

// ---------------------------------------------------------------------------------------------
// The cache, shape C: `entries` maps a key to its value and last-use tick, `by-tick` maps each
// live tick to its key. The least recently used key has the smallest live tick.

val lehmer-m = 2147483647
val lehmer-a = 48271
val seed = 42
val hot-percent = 80
val modulus = 1000000007

value struct entry(value : int, tick : int)

fun pick-key(state : int, capacity : int) : int
  val draw = state / 100
  if state % 100 < hot-percent then draw % capacity
  else capacity + draw % (capacity * 15)

struct result(hits : int, misses : int, values : int, by-tick : tree<int>)

fun run(ops : int, capacity : int, state : int, entries : tree<entry>, by-tick : tree<int>,
        clock : int, size : int, hits : int, misses : int, values : int) : div result
  if ops == 0 then Result(hits, misses, values, by-tick) else
    val next = (state * lehmer-a) % lehmer-m
    val key = pick-key(next, capacity)
    match entries.lookup(key)
      Just(Entry(value, old)) ->
        val ticks = by-tick.remove(old).insert(clock, key)
        run(ops - 1, capacity, next, entries.insert(key, Entry(value, clock)), ticks,
            clock + 1, size, hits + 1, misses, (values + value) % modulus)
      Nothing ->
        val (entries1, ticks1, size1) =
          if size < capacity then (entries, by-tick, size + 1)
          else match by-tick.minimum
            Just((t, k)) -> (entries.remove(k), by-tick.remove(t), size)
            Nothing -> (entries, by-tick, size + 1)
        run(ops - 1, capacity, next, entries1.insert(key, Entry(key * 2 + 1, clock)),
            ticks1.insert(clock, key), clock + 1, size1, hits, misses + 1, values)

pub fun main()
  val args = get-args()
  val capacity = args.head.default("1").parse-int.default(1)
  val ops = args.drop(1).head.default("0").parse-int.default(0)
  val Result(hits, misses, values, by-tick) = run(ops, capacity, seed, Leaf, Leaf, 0, 0, 0, 0, 0)
  val (checksum, _) = by-tick.fold((0, 1)) fn(_, key, (sum, position))
    ((sum + position * key) % modulus, position + 1)
  println("hits " ++ hits.show)
  println("misses " ++ misses.show)
  println("values " ++ values.show)
  println("checksum " ++ checksum.show)
