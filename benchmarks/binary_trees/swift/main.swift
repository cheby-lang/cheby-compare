// Binary-trees: allocates and walks many short-lived perfect binary trees.
//
// The first argument is the maximum depth n. The program checks a stretch tree of depth n + 1,
// keeps a long-lived tree of depth n, and then builds and checks 2^(n - d + 4) trees of each
// depth d = 4, 6, ..., n. A tree's check is its number of nodes.

let minDepth = 4

final class Node {
  let left: Node?
  let right: Node?

  init(left: Node?, right: Node?) {
    self.left = left
    self.right = right
  }
}

/// A perfect binary tree of depth `depth`, which has 2^(depth + 1) - 1 nodes.
func make(_ depth: Int) -> Node {
  if depth == 0 {
    return Node(left: nil, right: nil)
  }
  return Node(left: make(depth - 1), right: make(depth - 1))
}

/// The number of nodes of `node`.
func check(_ node: Node) -> Int {
  1 + (node.left.map(check) ?? 0) + (node.right.map(check) ?? 0)
}

let maxDepth = Int(CommandLine.arguments[1])!

let stretchDepth = maxDepth + 1
print("stretch tree of depth \(stretchDepth)\t check: \(check(make(stretchDepth)))")

let longLived = make(maxDepth)

for depth in stride(from: minDepth, through: maxDepth, by: 2) {
  let iterations = 1 << (maxDepth - depth + minDepth)
  var total = 0
  for _ in 0..<iterations {
    total += check(make(depth))
  }
  print("\(iterations)\t trees of depth \(depth)\t check: \(total)")
}

print("long lived tree of depth \(maxDepth)\t check: \(check(longLived))")
