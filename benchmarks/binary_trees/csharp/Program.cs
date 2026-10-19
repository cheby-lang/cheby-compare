// Binary-trees: allocates and walks many short-lived perfect binary trees.
// The argument is the maximum depth n. Checks a stretch tree of depth n + 1, keeps a long-lived
// tree of depth n, then builds and checks 2^(n - d + 4) trees of each depth d = 4, 6, ..., n.
using System.Globalization;

const int MinDepth = 4;

int maxDepth = int.Parse(args[0], CultureInfo.InvariantCulture);

int stretchDepth = maxDepth + 1;
Console.WriteLine($"stretch tree of depth {stretchDepth}\t check: {Node.Make(stretchDepth).Check()}");

Node longLived = Node.Make(maxDepth);

for (int depth = MinDepth; depth <= maxDepth; depth += 2)
{
    long iterations = 1L << (maxDepth - depth + MinDepth);
    long total = 0;
    for (long i = 0; i < iterations; i++)
    {
        total += Node.Make(depth).Check();
    }
    Console.WriteLine($"{iterations}\t trees of depth {depth}\t check: {total}");
}

Console.WriteLine($"long lived tree of depth {maxDepth}\t check: {longLived.Check()}");

sealed class Node(Node? left, Node? right)
{
    readonly Node? left = left;
    readonly Node? right = right;

    // A perfect binary tree of the given depth, which has 2^(depth + 1) - 1 nodes.
    public static Node Make(int depth) =>
        depth == 0 ? new Node(null, null) : new Node(Make(depth - 1), Make(depth - 1));

    // The number of nodes, by walking the tree.
    public long Check() => 1 + (left?.Check() ?? 0) + (right?.Check() ?? 0);
}
