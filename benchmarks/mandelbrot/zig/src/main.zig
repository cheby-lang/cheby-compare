//! Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.

const std = @import("std");

const max_iter = 50;

/// The number of iterations before the point (cr, ci) escapes, or `max_iter`.
fn escapeTime(cr: f64, ci: f64) u32 {
    var zr: f64 = 0.0;
    var zi: f64 = 0.0;
    var i: u32 = 0;
    while (i < max_iter) : (i += 1) {
        const zr2 = zr * zr;
        const zi2 = zi * zi;
        if (zr2 + zi2 > 4.0) break;
        zi = 2.0 * zr * zi + ci;
        zr = zr2 - zi2 + cr;
    }
    return i;
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const n = try std.fmt.parseInt(u64, args[1], 10);
    const nf: f64 = @floatFromInt(n);

    var inside: u64 = 0;
    var iterations: u64 = 0;
    var checksum: u64 = 0;
    for (0..n) |y| {
        const ci = 2.0 * @as(f64, @floatFromInt(y)) / nf - 1.0;
        for (0..n) |x| {
            const cr = 2.0 * @as(f64, @floatFromInt(x)) / nf - 1.5;
            const i = escapeTime(cr, ci);
            iterations += i;
            if (i == max_iter) {
                inside += 1;
                checksum += y * n + x;
            }
        }
    }

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("inside {d}\n", .{inside});
    try stdout.print("iterations {d}\n", .{iterations});
    try stdout.print("checksum {d}\n", .{checksum % (1 << 32)});
    try stdout.flush();
}
