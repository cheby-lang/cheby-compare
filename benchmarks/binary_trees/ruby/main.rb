# Binary-trees: allocates and walks many short-lived perfect binary trees.
#
# The first argument is the maximum depth n. The program checks a stretch tree
# of depth n + 1, keeps a long-lived tree of depth n, and then builds and checks
# 2^(n - d + 4) trees of each depth d = 4, 6, ..., n. A tree's check is its
# number of nodes.

MIN_DEPTH = 4

class Node
  attr_reader :left, :right

  def initialize(left, right)
    @left = left
    @right = right
  end
end

# A perfect binary tree of depth `depth`, with 2^(depth + 1) - 1 nodes.
def make(depth)
  return Node.new(nil, nil) if depth == 0

  Node.new(make(depth - 1), make(depth - 1))
end

# The number of nodes of `node`.
def check(node)
  left = node.left
  right = node.right
  1 + (left ? check(left) : 0) + (right ? check(right) : 0)
end

max_depth = Integer(ARGV[0])

stretch_depth = max_depth + 1
puts "stretch tree of depth #{stretch_depth}\t check: #{check(make(stretch_depth))}"

long_lived = make(max_depth)

MIN_DEPTH.step(max_depth, 2) do |depth|
  iterations = 1 << (max_depth - depth + MIN_DEPTH)
  total = 0
  iterations.times { total += check(make(depth)) }
  puts "#{iterations}\t trees of depth #{depth}\t check: #{total}"
end

puts "long lived tree of depth #{max_depth}\t check: #{check(long_lived)}"
