// Binary-trees: allocates and walks many short-lived perfect binary trees.
//
// The first argument is the maximum depth n. The program checks a stretch tree of depth n + 1,
// keeps a long-lived tree of depth n, and then builds and checks 2^(n - d + 4) trees of each
// depth d = 4, 6, ..., n. A tree's check is its number of nodes.

#include <cstdint>
#include <iostream>
#include <memory>
#include <string>

namespace {

constexpr int min_depth = 4;

struct Node {
    std::unique_ptr<Node> left;
    std::unique_ptr<Node> right;
};

// A perfect binary tree of depth `depth`, which has 2^(depth + 1) - 1 nodes.
std::unique_ptr<Node> make(int depth) {
    auto node = std::make_unique<Node>();
    if (depth > 0) {
        node->left = make(depth - 1);
        node->right = make(depth - 1);
    }
    return node;
}

// The number of nodes of `node`.
std::int64_t check(const Node& node) {
    return 1 + (node.left ? check(*node.left) : 0) + (node.right ? check(*node.right) : 0);
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main <max depth>\n";
        return 1;
    }
    const int max_depth = std::stoi(argv[1]);

    const int stretch_depth = max_depth + 1;
    std::cout << "stretch tree of depth " << stretch_depth << "\t check: "
              << check(*make(stretch_depth)) << '\n';

    const auto long_lived = make(max_depth);

    for (int depth = min_depth; depth <= max_depth; depth += 2) {
        const std::int64_t iterations = std::int64_t{1} << (max_depth - depth + min_depth);
        std::int64_t total = 0;
        for (std::int64_t i = 0; i < iterations; ++i) {
            total += check(*make(depth));
        }
        std::cout << iterations << "\t trees of depth " << depth << "\t check: " << total << '\n';
    }

    std::cout << "long lived tree of depth " << max_depth << "\t check: " << check(*long_lived)
              << '\n';
}
