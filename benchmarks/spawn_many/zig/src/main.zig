//! spawn_many: spawns one OS thread per index in batches of 1,000, joins each batch and
//! prints the sum of the results.

const std = @import("std");

const batch_size = 1000;
const rounds = 10;
const modulus = 2147483647; // 2^31 - 1
const multiplier = 48271; // the MINSTD generator

/// Ten MINSTD steps from `index + 1`.
fn work(index: u64) u64 {
    var x = index + 1;
    for (0..rounds) |_| {
        x = (x * multiplier) % modulus;
    }
    return x;
}

/// The body of one thread: computes `work(index)` into its own slot.
fn task(index: u64, slot: *u64) void {
    slot.* = work(index);
}

/// Spawns one thread per index in `start .. start + count`, joins them all and returns the
/// sum of their results.
fn spawnAndJoin(gpa: std.mem.Allocator, start: u64, count: usize) !u64 {
    const results = try gpa.alloc(u64, count);
    defer gpa.free(results);
    const threads = try gpa.alloc(std.Thread, count);
    defer gpa.free(threads);

    for (threads, results, 0..) |*thread, *slot, j| {
        thread.* = try std.Thread.spawn(.{}, task, .{ start + j, slot });
    }
    for (threads) |thread| thread.join();

    var sum: u64 = 0;
    for (results) |r| sum += r;
    return sum;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const n = try std.fmt.parseInt(u64, args[1], 10);

    var sum: u64 = 0;
    var start: u64 = 0;
    while (start < n) : (start += batch_size) {
        sum += try spawnAndJoin(gpa, start, @intCast(@min(batch_size, n - start)));
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("tasks: {d}\nsum: {d}\n", .{ n, sum });
    try stdout.flush();
}
