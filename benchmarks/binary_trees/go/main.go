// Binary-trees: allocates and walks many short-lived perfect binary trees.
//
// The first argument is the maximum depth n. The program checks a stretch tree of depth n+1,
// keeps a long-lived tree of depth n, and then builds and checks 2^(n-d+4) trees of each depth
// d = 4, 6, ..., n. A tree's check is its number of nodes.
package main

import (
	"fmt"
	"os"
	"strconv"
)

const minDepth = 4

// Node is one tree node; nil children are absent.
type Node struct {
	left, right *Node
}

// makeTree builds a perfect binary tree of the given depth.
func makeTree(depth int) *Node {
	if depth == 0 {
		return &Node{}
	}
	return &Node{left: makeTree(depth - 1), right: makeTree(depth - 1)}
}

// check counts the nodes of the tree by walking it.
func check(t *Node) int64 {
	n := int64(1)
	if t.left != nil {
		n += check(t.left)
	}
	if t.right != nil {
		n += check(t.right)
	}
	return n
}

func main() {
	n, err := strconv.Atoi(os.Args[1])
	if err != nil || n < 0 {
		fmt.Fprintln(os.Stderr, "usage: main <max depth>")
		os.Exit(2)
	}

	stretchDepth := n + 1
	fmt.Printf("stretch tree of depth %d\t check: %d\n", stretchDepth, check(makeTree(stretchDepth)))

	longLived := makeTree(n)

	for d := minDepth; d <= n; d += 2 {
		iterations := int64(1) << (n - d + minDepth)
		total := int64(0)
		for range iterations {
			total += check(makeTree(d))
		}
		fmt.Printf("%d\t trees of depth %d\t check: %d\n", iterations, d, total)
	}

	fmt.Printf("long lived tree of depth %d\t check: %d\n", n, check(longLived))
}
