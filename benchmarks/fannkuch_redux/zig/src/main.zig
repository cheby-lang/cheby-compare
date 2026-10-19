//! Fannkuch-redux: flips over every permutation of 0..n, in the order the counting algorithm
//! generates them. Prints the alternating checksum and the maximum flip count.

const std = @import("std");

const max_n = 12;

const Result = struct { checksum: i64, max_flips: i64 };

/// Returns the checksum and the maximum flip count over all permutations of 0..n, 1 <= n <= 12.
fn fannkuch(n: usize) Result {
    var perm1_buf: [max_n]usize = undefined;
    var perm_buf: [max_n]usize = undefined;
    var count_buf: [max_n]usize = @splat(0);
    const perm1 = perm1_buf[0..n];
    const perm = perm_buf[0..n];
    const count = count_buf[0..n];
    for (perm1, 0..) |*p, i| p.* = i;

    var max_flips: i64 = 0;
    var checksum: i64 = 0;
    var perm_index: u64 = 0;
    var r = n;
    while (true) : (perm_index += 1) {
        while (r != 1) : (r -= 1) count[r - 1] = r;

        @memcpy(perm, perm1);
        var flips: i64 = 0;
        var k = perm[0];
        while (k != 0) : (k = perm[0]) {
            std.mem.reverse(usize, perm[0 .. k + 1]);
            flips += 1;
        }
        max_flips = @max(max_flips, flips);
        checksum += if (perm_index % 2 == 0) flips else -flips;

        while (true) {
            if (r == n) return .{ .checksum = checksum, .max_flips = max_flips };
            std.mem.rotate(usize, perm1[0 .. r + 1], 1);
            count[r] -= 1;
            if (count[r] > 0) break;
            r += 1;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const n = try std.fmt.parseInt(usize, args[1], 10);
    if (n > max_n) return error.TooLarge;

    const result = fannkuch(@max(n, 1));

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{d}\n", .{result.checksum});
    try stdout.print("Pfannkuchen({d}) = {d}\n", .{ n, result.max_flips });
    try stdout.flush();
}
