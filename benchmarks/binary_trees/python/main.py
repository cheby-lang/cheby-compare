"""Binary-trees: allocates and walks many short-lived perfect binary trees.

The first argument is the maximum depth n. The program checks a stretch tree
of depth n + 1, keeps a long-lived tree of depth n, and then builds and checks
2^(n - d + 4) trees of each depth d = 4, 6, ..., n. A tree's check is its
number of nodes.
"""

import sys

MIN_DEPTH = 4


class Node:
    __slots__ = ("left", "right")

    def __init__(self, left, right):
        self.left = left
        self.right = right


def make(depth):
    """A perfect binary tree of depth `depth`, with 2^(depth + 1) - 1 nodes."""
    if depth == 0:
        return Node(None, None)
    return Node(make(depth - 1), make(depth - 1))


def check(node):
    """The number of nodes of `node`."""
    left = node.left
    right = node.right
    return (
        1
        + (check(left) if left is not None else 0)
        + (check(right) if right is not None else 0)
    )


def main():
    max_depth = int(sys.argv[1])

    stretch_depth = max_depth + 1
    print(f"stretch tree of depth {stretch_depth}\t check: {check(make(stretch_depth))}")

    long_lived = make(max_depth)

    for depth in range(MIN_DEPTH, max_depth + 1, 2):
        iterations = 1 << (max_depth - depth + MIN_DEPTH)
        total = 0
        for _ in range(iterations):
            total += check(make(depth))
        print(f"{iterations}\t trees of depth {depth}\t check: {total}")

    print(f"long lived tree of depth {max_depth}\t check: {check(long_lived)}")


if __name__ == "__main__":
    main()
