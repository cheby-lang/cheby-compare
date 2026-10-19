// Binary-trees: allocates and walks many short-lived perfect binary trees.
//
// The first argument is the maximum depth n. The program checks a stretch tree of depth n + 1,
// keeps a long-lived tree of depth n, and then builds and checks 2^(n - d + 4) trees of each
// depth d = 4, 6, ..., n. A tree's check is its number of nodes.
public class Main {
    private static final int MIN_DEPTH = 4;

    /** A tree node with no payload; null children are absent. */
    static final class Node {
        final Node left;
        final Node right;

        Node(Node left, Node right) {
            this.left = left;
            this.right = right;
        }
    }

    /** A perfect binary tree of the given depth, which has 2^(depth + 1) - 1 nodes. */
    static Node make(int depth) {
        if (depth == 0) {
            return new Node(null, null);
        }
        return new Node(make(depth - 1), make(depth - 1));
    }

    /** The number of nodes of the tree, by walking it. */
    static long check(Node node) {
        return 1
                + (node.left != null ? check(node.left) : 0)
                + (node.right != null ? check(node.right) : 0);
    }

    public static void main(String[] args) {
        int maxDepth = Integer.parseInt(args[0]);
        StringBuilder out = new StringBuilder();

        int stretchDepth = maxDepth + 1;
        out.append("stretch tree of depth ").append(stretchDepth)
                .append("\t check: ").append(check(make(stretchDepth))).append('\n');

        Node longLived = make(maxDepth);

        for (int depth = MIN_DEPTH; depth <= maxDepth; depth += 2) {
            long iterations = 1L << (maxDepth - depth + MIN_DEPTH);
            long total = 0;
            for (long i = 0; i < iterations; i++) {
                total += check(make(depth));
            }
            out.append(iterations).append("\t trees of depth ").append(depth)
                    .append("\t check: ").append(total).append('\n');
        }

        out.append("long lived tree of depth ").append(maxDepth)
                .append("\t check: ").append(check(longLived)).append('\n');
        System.out.print(out);
    }
}
