// binary-trees: builds and walks many perfect binary trees to stress allocation and the GC.

class TreeNode {
  constructor(
    readonly left: TreeNode | null,
    readonly right: TreeNode | null,
  ) {}
}

const MIN_DEPTH = 4;

function make(depth: number): TreeNode {
  if (depth === 0) return new TreeNode(null, null);
  const left = make(depth - 1);
  const right = make(depth - 1);
  return new TreeNode(left, right);
}

function check(tree: TreeNode): number {
  return (
    1 +
    (tree.left !== null ? check(tree.left) : 0) +
    (tree.right !== null ? check(tree.right) : 0)
  );
}

function main(n: number): void {
  const lines: string[] = [];
  const stretchDepth = n + 1;
  lines.push(`stretch tree of depth ${stretchDepth}\t check: ${check(make(stretchDepth))}`);

  const longLived = make(n);

  for (let d = MIN_DEPTH; d <= n; d += 2) {
    const iterations = 2 ** (n - d + MIN_DEPTH);
    let total = 0;
    for (let i = 0; i < iterations; i++) {
      total += check(make(d));
    }
    lines.push(`${iterations}\t trees of depth ${d}\t check: ${total}`);
  }

  lines.push(`long lived tree of depth ${n}\t check: ${check(longLived)}`);
  process.stdout.write(lines.join("\n") + "\n");
}

main(Number.parseInt(process.argv[2] ?? "0", 10));
