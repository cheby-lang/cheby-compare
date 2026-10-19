# binary_trees: builds and walks many perfect binary trees, single-threaded.
# Prints the node count of a stretch tree, of each batch of trees and of a long-lived tree.

import std/[os, strutils]

type
  Node {.acyclic.} = ref object
    left, right: Node

const minDepth = 4

proc make(d: int): Node =
  if d == 0:
    Node()
  else:
    let left = make(d - 1)
    let right = make(d - 1)
    Node(left: left, right: right)

proc check(t: Node): int =
  result = 1
  if t.left != nil: result += check(t.left)
  if t.right != nil: result += check(t.right)

proc main() =
  let n = parseInt(paramStr(1))
  let stretchDepth = n + 1
  stdout.write "stretch tree of depth ", stretchDepth, "\t check: ",
    check(make(stretchDepth)), "\n"

  let longLived = make(n)

  var d = minDepth
  while d <= n:
    let iterations = 1 shl (n - d + minDepth)
    var total = 0
    for _ in 1 .. iterations:
      total += check(make(d))
    stdout.write iterations, "\t trees of depth ", d, "\t check: ", total, "\n"
    d += 2

  stdout.write "long lived tree of depth ", n, "\t check: ", check(longLived), "\n"

main()
