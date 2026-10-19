// word_freq: counts the words of a file in a red-black tree, merge-sorts the counts and prints the top 20.

import std/os/env
import std/os/file
import std/os/path

// A persistent red-black tree from words to counts, updated in place (FBIP) when it is unique.
type color
  Red
  Black

type tree
  Node(color : color, left : tree, key : string, count : int, right : tree)
  Leaf

// The reverse path from the current node up to the root.
type zipper
  NodeR(color : color, left : tree, key : string, count : int, up : zipper)
  NodeL(color : color, up : zipper, key : string, count : int, right : tree)
  Done

fip fun move-up(z : zipper, t : tree) : tree
  match z
    NodeR(c, l, k, n, up) -> up.move-up(Node(c, l, k, n, t))
    NodeL(c, up, k, n, r) -> up.move-up(Node(c, t, k, n, r))
    Done -> t

fip(1) fun balance-red(z : zipper, l : tree, k : string, n : int, r : tree) : tree
  match z
    NodeR(Black, l1, k1, n1, z1) -> z1.move-up(Node(Black, l1, k1, n1, Node(Red, l, k, n, r)))
    NodeL(Black, z1, k1, n1, r1) -> z1.move-up(Node(Black, Node(Red, l, k, n, r), k1, n1, r1))
    NodeR(Red, l1, k1, n1, z1) -> match z1
      NodeR(_, l2, k2, n2, z2) -> z2.balance-red(Node(Black, l2, k2, n2, l1), k1, n1, Node(Black, l, k, n, r))
      NodeL(_, z2, k2, n2, r2) -> z2.balance-red(Node(Black, l1, k1, n1, l), k, n, Node(Black, r, k2, n2, r2))
      Done -> Node(Black, l1, k1, n1, Node(Red, l, k, n, r))
    NodeL(Red, z1, k1, n1, r1) -> match z1
      NodeR(_, l2, k2, n2, z2) -> z2.balance-red(Node(Black, l2, k2, n2, l), k, n, Node(Black, r, k1, n1, r1))
      NodeL(_, z2, k2, n2, r2) -> z2.balance-red(Node(Black, l, k, n, r), k1, n1, Node(Black, r1, k2, n2, r2))
      Done -> Node(Black, Node(Red, l, k, n, r), k1, n1, r1)
    Done -> Node(Black, l, k, n, r)

// Adds one to the count of `word`, inserting it with count 1 when absent.
fun increment(t : tree, word : string, z : zipper) : tree
  match t
    Node(c, l, k, n, r) -> match cmp(word, k)
      Lt -> increment(l, word, NodeL(c, z, k, n, r))
      Gt -> increment(r, word, NodeR(c, l, k, n, z))
      Eq -> z.move-up(Node(c, l, k, n + 1, r))
    Leaf -> z.balance-red(Leaf, word, 1, Leaf)

// The entries in ascending key order, built from the right so no reverse is needed.
fun entries(t : tree, acc : list<(string, int)>) : list<(string, int)>
  match t
    Node(_, l, k, n, r) -> entries(l, Cons((k, n), entries(r, acc)))
    Leaf -> acc

fun size(t : tree) : int
  match t
    Node(_, l, _, _, r) -> size(l) + 1 + size(r)
    Leaf -> 0

// By count descending, then word ascending (byte order).
fun before(a : (string, int), b : (string, int)) : bool
  val (wa, na) = a
  val (wb, nb) = b
  na > nb || (na == nb && wa < wb)

fun merge(xs : list<(string, int)>, ys : list<(string, int)>) : list<(string, int)>
  match xs
    Nil -> ys
    Cons(x, xx) -> match ys
      Nil -> xs
      Cons(y, yy) -> if before(y, x) then Cons(y, merge(xs, yy)) else Cons(x, merge(xx, ys))

// A top-down merge sort, stable: the first half wins ties.
fun msort(xs : list<(string, int)>, n : int) : div list<(string, int)>
  if n <= 1 then xs else
    val half = n / 2
    val (front, back) = xs.split(half)
    merge(msort(front, half), msort(back, n - half))

// Counts the words of the lines, line by line; empty parts are skipped.
fun count-words(lines : list<string>, words : list<string>, t : tree, total : int) : (tree, int)
  match words
    Cons(w, ws) ->
      if w.is-empty then count-words(lines, ws, t, total)
      else count-words(lines, ws, t.increment(w, Done), total + 1)
    Nil -> match lines
      Cons(line, rest) -> count-words(rest, line.split(" "), t, total)
      Nil -> (t, total)

pub fun main()
  val name = get-args().head.default("")
  val text = read-text-file(path(name))
  val (counts, total) = count-words(text.split("\n"), Nil, Leaf, 0)
  val distinct = counts.size
  val sorted = msort(counts.entries(Nil), distinct)
  println("total " ++ total.show)
  println("distinct " ++ distinct.show)
  sorted.take(20).foreach fn((w, n))
    println(n.show ++ " " ++ w)
