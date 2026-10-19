//! Spectral norm: the benchmarks-game power method on the matrix
//! A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.

const std = @import("std");

/// The entry A(i, j) of the matrix.
fn entry(i: usize, j: usize) f64 {
    return 1.0 / @as(f64, @floatFromInt((i + j) * (i + j + 1) / 2 + i + 1));
}

/// Writes A times `x` into `out`.
fn timesA(x: []const f64, out: []f64) void {
    for (out, 0..) |*o, i| {
        var sum: f64 = 0.0;
        for (x, 0..) |xj, j| sum += entry(i, j) * xj;
        o.* = sum;
    }
}

/// Writes A transposed times `x` into `out`.
fn timesAt(x: []const f64, out: []f64) void {
    for (out, 0..) |*o, i| {
        var sum: f64 = 0.0;
        for (x, 0..) |xj, j| sum += entry(j, i) * xj;
        o.* = sum;
    }
}

/// Writes A transposed times A times `x` into `out`, using `tmp`.
fn timesAtA(x: []const f64, tmp: []f64, out: []f64) void {
    timesA(x, tmp);
    timesAt(tmp, out);
}

fn dot(x: []const f64, y: []const f64) f64 {
    var sum: f64 = 0.0;
    for (x, y) |a, b| sum += a * b;
    return sum;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const n = try std.fmt.parseInt(usize, args[1], 10);

    const u = try gpa.alloc(f64, n);
    defer gpa.free(u);
    const v = try gpa.alloc(f64, n);
    defer gpa.free(v);
    const tmp = try gpa.alloc(f64, n);
    defer gpa.free(tmp);
    @memset(u, 1.0);
    @memset(v, 0.0);

    for (0..10) |_| {
        timesAtA(u, tmp, v);
        timesAtA(v, tmp, u);
    }

    const vv = dot(v, v);
    const result: i64 = if (vv == 0.0) 0 else @intFromFloat(@round(@sqrt(dot(u, v) / vv) * 1e9));

    var stdout_buffer: [64]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{d}\n", .{result});
    try stdout.flush();
}
