//! prime_sieve: the concurrent prime sieve. The generator and every filter are concurrent
//! tasks of one `std.Io.Group` on the default `std.Io.Threaded`, connected by rendezvous queues.

const std = @import("std");
const Io = std.Io;

const Channel = Io.Queue(i64);

/// Sends 2, 3, 4 and so on to `out`, until the process ends.
fn generate(io: Io, out: *Channel) Io.Cancelable!void {
    var i: i64 = 2;
    while (true) : (i += 1) {
        out.putOne(io, i) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => |e| return e,
        };
    }
}

/// Passes on the numbers from `in` that `prime` does not divide, until the process ends.
fn filter(io: Io, in: *Channel, out: *Channel, prime: i64) Io.Cancelable!void {
    while (true) {
        const m = in.getOne(io) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => |e| return e,
        };
        if (@rem(m, prime) != 0) {
            out.putOne(io, m) catch |err| switch (err) {
                error.Closed => return,
                error.Canceled => |e| return e,
            };
        }
    }
}

/// A new rendezvous queue on the heap, so its address stays fixed while tasks use it.
fn newChannel(gpa: std.mem.Allocator) !*Channel {
    const ch = try gpa.create(Channel);
    ch.* = .init(&.{});
    return ch;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const n = try std.fmt.parseInt(u32, args[1], 10);

    var group: Io.Group = .init;
    var ch = try newChannel(gpa);
    try group.concurrent(io, generate, .{ io, ch });

    var last: i64 = 0;
    var sum: i64 = 0;
    for (0..n) |_| {
        const prime = try ch.getOne(io);
        last = prime;
        sum += prime;
        const next = try newChannel(gpa);
        try group.concurrent(io, filter, .{ io, ch, next, prime });
        ch = next;
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("primes: {d}\nlast: {d}\nsum: {d}\n", .{ n, last, sum });
    try stdout.flush();

    // Shut down with the stages still blocked (SPEC, "Shut down", option 1): the group is
    // never awaited and the queues are never freed.
    std.process.exit(0);
}
