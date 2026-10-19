//! Binary-trees: allocates and walks many short-lived perfect binary trees.
//!
//! The first argument is the maximum depth `n`. The program checks a stretch tree of depth
//! `n + 1`, keeps a long-lived tree of depth `n`, and then builds and checks `2^(n - d + 4)` trees
//! of each depth `d = 4, 6, ..., n`. A tree's check is its number of nodes. Every node is one
//! allocation from `std.heap.smp_allocator`, freed node by node after the check.

const std = @import("std");
const Allocator = std.mem.Allocator;

const min_depth = 4;

const Node = struct {
    left: ?*Node,
    right: ?*Node,
};

/// A perfect binary tree of depth `depth`, which has `2^(depth + 1) - 1` nodes.
fn make(gpa: Allocator, depth: u32) Allocator.Error!*Node {
    const node = try gpa.create(Node);
    if (depth == 0) {
        node.* = .{ .left = null, .right = null };
    } else {
        const left = try make(gpa, depth - 1);
        const right = try make(gpa, depth - 1);
        node.* = .{ .left = left, .right = right };
    }
    return node;
}

/// The number of nodes of `node`.
fn check(node: *const Node) u64 {
    var count: u64 = 1;
    if (node.left) |left| count += check(left);
    if (node.right) |right| count += check(right);
    return count;
}

/// Frees every node of the tree.
fn free(gpa: Allocator, node: *Node) void {
    if (node.left) |left| free(gpa, left);
    if (node.right) |right| free(gpa, right);
    gpa.destroy(node);
}

pub fn main(init: std.process.Init) !void {
    const gpa = std.heap.smp_allocator;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const max_depth = try std.fmt.parseInt(u32, args[1], 10);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const stretch_depth = max_depth + 1;
    const stretch = try make(gpa, stretch_depth);
    try stdout.print("stretch tree of depth {d}\t check: {d}\n", .{ stretch_depth, check(stretch) });
    free(gpa, stretch);

    const long_lived = try make(gpa, max_depth);

    var depth: u32 = min_depth;
    while (depth <= max_depth) : (depth += 2) {
        const iterations = @as(u64, 1) << @intCast(max_depth - depth + min_depth);
        var total: u64 = 0;
        var i: u64 = 0;
        while (i < iterations) : (i += 1) {
            const tree = try make(gpa, depth);
            total += check(tree);
            free(gpa, tree);
        }
        try stdout.print("{d}\t trees of depth {d}\t check: {d}\n", .{ iterations, depth, total });
    }

    try stdout.print("long lived tree of depth {d}\t check: {d}\n", .{ max_depth, check(long_lived) });
    free(gpa, long_lived);
    try stdout.flush();
}
