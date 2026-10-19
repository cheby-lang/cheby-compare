//! word_freq: counts the words of a file and prints the 20 most frequent.

const std = @import("std");

const top = 20;

const Entry = struct {
    word: []const u8,
    count: u64,
};

fn moreFrequent(_: void, a: Entry, b: Entry) bool {
    if (a.count != b.count) return a.count > b.count;
    return std.mem.order(u8, a.word, b.word) == .lt;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .unlimited);
    defer gpa.free(text);

    // Keys are slices into `text`.
    var counts: std.StringHashMap(u64) = .init(gpa);
    defer counts.deinit();
    var total: u64 = 0;
    var words = std.mem.tokenizeAny(u8, text, " \n");
    while (words.next()) |word| {
        const slot = try counts.getOrPut(word);
        if (!slot.found_existing) slot.value_ptr.* = 0;
        slot.value_ptr.* += 1;
        total += 1;
    }

    var ranked: std.ArrayList(Entry) = try .initCapacity(gpa, counts.count());
    defer ranked.deinit(gpa);
    var it = counts.iterator();
    while (it.next()) |kv| {
        ranked.appendAssumeCapacity(.{ .word = kv.key_ptr.*, .count = kv.value_ptr.* });
    }
    std.mem.sort(Entry, ranked.items, {}, moreFrequent);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("total {d}\n", .{total});
    try stdout.print("distinct {d}\n", .{ranked.items.len});
    for (ranked.items[0..@min(top, ranked.items.len)]) |e| {
        try stdout.print("{d} {s}\n", .{ e.count, e.word });
    }
    try stdout.flush();
}
