// binary_trees: builds and walks perfect binary trees, one heap node per constructor.

import std/os/env

type tree
  Empty
  Node(left : tree, right : tree)

val min-depth = 4

// A perfect tree of depth d: the left subtree first, then the right.
fun make(d : int) : div tree
  if d == 0 then Node(Empty, Empty) else
    val l = make(d - 1)
    val r = make(d - 1)
    Node(l, r)

// The number of nodes, by walking both children of every node.
fun check(t : tree) : int
  match t
    Empty -> 0
    Node(l, r) -> 1 + check(l) + check(r)

// Builds and checks `remaining` trees of depth d, summing their counts.
fun sum-trees(d : int, remaining : int, total : int) : div int
  if remaining == 0 then total
  else sum-trees(d, remaining - 1, total + check(make(d)))

fun depths(d : int, n : int) : <console,div> ()
  if d <= n then
    val iterations = exp2(n - d + min-depth)
    val total = sum-trees(d, iterations, 0)
    println(iterations.show ++ "\t trees of depth " ++ d.show ++ "\t check: " ++ total.show)
    depths(d + 2, n)

pub fun main()
  val n = get-args().head.default("0").parse-int.default(0)
  val stretch = n + 1
  println("stretch tree of depth " ++ stretch.show ++ "\t check: " ++ check(make(stretch)).show)
  val long-lived = make(n)
  depths(min-depth, n)
  println("long lived tree of depth " ++ n.show ++ "\t check: " ++ check(long-lived).show)
