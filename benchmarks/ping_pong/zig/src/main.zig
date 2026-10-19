//! ping_pong: the main thread (task A) and one concurrent task (B) of the default
//! `std.Io.Threaded` pass `n` numbers back and forth over two rendezvous queues.

const std = @import("std");
const Io = std.Io;

/// Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
fn echo(io: Io, n: i64, ping: *Io.Queue(i64), pong: *Io.Queue(i64)) !void {
    var round: i64 = 0;
    while (round < n) : (round += 1) {
        const x = try ping.getOne(io);
        try pong.putOne(io, x + 1);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const n = try std.fmt.parseInt(i64, args[1], 10);

    // A zero-length buffer makes each queue a rendezvous: `putOne` waits for a getter.
    var ping: Io.Queue(i64) = .init(&.{});
    var pong: Io.Queue(i64) = .init(&.{});
    var b = try io.concurrent(echo, .{ io, n, &ping, &pong });

    var sum: i64 = 0;
    var i: i64 = 1;
    while (i <= n) : (i += 1) {
        try ping.putOne(io, i);
        sum += try pong.getOne(io);
    }
    try b.await(io);

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{d}\n{d}\n", .{ n, sum });
    try stdout.flush();
}
