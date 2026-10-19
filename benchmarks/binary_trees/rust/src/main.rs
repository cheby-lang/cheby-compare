//! Binary-trees: allocates and walks many short-lived perfect binary trees.
//!
//! The first argument is the maximum depth `n`. The program checks a stretch
//! tree of depth `n + 1`, keeps a long-lived tree of depth `n`, and then builds
//! and checks `2^(n - d + 4)` trees of each depth `d = 4, 6, ..., n`. A tree's
//! check is its number of nodes.

const MIN_DEPTH: u32 = 4;

struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

/// A perfect binary tree of depth `depth`, which has `2^(depth + 1) - 1` nodes.
fn make(depth: u32) -> Box<Node> {
    if depth == 0 {
        Box::new(Node {
            left: None,
            right: None,
        })
    } else {
        Box::new(Node {
            left: Some(make(depth - 1)),
            right: Some(make(depth - 1)),
        })
    }
}

/// The number of nodes of `node`.
fn check(node: &Node) -> u64 {
    1 + node.left.as_deref().map_or(0, check) + node.right.as_deref().map_or(0, check)
}

fn main() {
    let max_depth: u32 = std::env::args()
        .nth(1)
        .and_then(|arg| arg.parse().ok())
        .expect("usage: main <max depth>");

    let stretch_depth = max_depth + 1;
    let stretch_check = check(&make(stretch_depth));
    println!("stretch tree of depth {stretch_depth}\t check: {stretch_check}");

    let long_lived = make(max_depth);

    for depth in (MIN_DEPTH..=max_depth).step_by(2) {
        let iterations: u64 = 1 << (max_depth - depth + MIN_DEPTH);
        let total: u64 = (0..iterations).map(|_| check(&make(depth))).sum();
        println!("{iterations}\t trees of depth {depth}\t check: {total}");
    }

    println!(
        "long lived tree of depth {max_depth}\t check: {}",
        check(&long_lived)
    );
}
