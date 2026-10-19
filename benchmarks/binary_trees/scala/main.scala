// Binary trees: builds and walks many perfect binary trees of small nodes, single-threaded.

/** A node with two children; `null` marks an absent child. */
final class Node(val left: Node, val right: Node)

val MinDepth = 4

/** A perfect tree of depth `d`, left subtree built first. */
def make(d: Int): Node =
  if d == 0 then Node(null, null)
  else
    val left = make(d - 1)
    val right = make(d - 1)
    Node(left, right)

/** The number of nodes, counted by walking both children of every node. */
def check(t: Node): Long =
  1L + (if t.left != null then check(t.left) else 0L) +
    (if t.right != null then check(t.right) else 0L)

@main def main(n: Int): Unit =
  val out = StringBuilder()
  val stretchDepth = n + 1
  out ++= s"stretch tree of depth $stretchDepth\t check: ${check(make(stretchDepth))}\n"

  val longLived = make(n)

  var d = MinDepth
  while d <= n do
    val iterations = 1L << (n - d + MinDepth)
    var total = 0L
    var i = 0L
    while i < iterations do
      total += check(make(d))
      i += 1
    out ++= s"$iterations\t trees of depth $d\t check: $total\n"
    d += 2

  out ++= s"long lived tree of depth $n\t check: ${check(longLived)}\n"
  print(out)
