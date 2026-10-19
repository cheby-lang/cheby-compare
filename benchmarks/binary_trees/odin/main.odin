// Binary-trees: allocates and walks many short-lived perfect binary trees.
//
// The first argument is the maximum depth n. The program checks a stretch
// tree of depth n + 1, keeps a long-lived tree of depth n, and then builds
// and checks 2^(n - d + 4) trees of each depth d = 4, 6, ..., n. A tree's
// check is its number of nodes.
package main

import "core:fmt"
import "core:os"
import "core:strconv"

MIN_DEPTH :: 4

Node :: struct {
	left:  ^Node,
	right: ^Node,
}

// A perfect binary tree of depth `depth`, one heap allocation per node.
make_tree :: proc(depth: int) -> ^Node {
	node := new(Node)
	if depth > 0 {
		node.left = make_tree(depth - 1)
		node.right = make_tree(depth - 1)
	}
	return node
}

// The number of nodes of `node`, by walking it.
check :: proc(node: ^Node) -> int {
	total := 1
	if node.left != nil {
		total += check(node.left)
	}
	if node.right != nil {
		total += check(node.right)
	}
	return total
}

free_tree :: proc(node: ^Node) {
	if node.left != nil {
		free_tree(node.left)
	}
	if node.right != nil {
		free_tree(node.right)
	}
	free(node)
}

main :: proc() {
	if len(os.args) < 2 {
		os.exit(2)
	}
	max_depth, ok := strconv.parse_int(os.args[1])
	if !ok || max_depth < 0 {
		os.exit(2)
	}

	stretch_depth := max_depth + 1
	stretch := make_tree(stretch_depth)
	fmt.printf("stretch tree of depth %d\t check: %d\n", stretch_depth, check(stretch))
	free_tree(stretch)

	long_lived := make_tree(max_depth)

	for depth := MIN_DEPTH; depth <= max_depth; depth += 2 {
		iterations := 1 << uint(max_depth - depth + MIN_DEPTH)
		total := 0
		for _ in 0 ..< iterations {
			tree := make_tree(depth)
			total += check(tree)
			free_tree(tree)
		}
		fmt.printf("%d\t trees of depth %d\t check: %d\n", iterations, depth, total)
	}

	fmt.printf("long lived tree of depth %d\t check: %d\n", max_depth, check(long_lived))
	free_tree(long_lived)
}
