//! json_roundtrip: parses a JSON array of records, transforms it and serializes it again.

const std = @import("std");

const fnv_offset: u32 = 2166136261;
const fnv_prime: u32 = 16777619;

const Address = struct {
    street: []const u8,
    city: []const u8,
    zip: i64,
};

const Entry = struct {
    day: i64,
    amount: i64,
};

const Record = struct {
    id: i64,
    name: []const u8,
    active: bool,
    score: i64,
    tags: []const []const u8,
    address: Address,
    history: []const Entry,
};

/// A kept record as it is written: `active` is gone, `score` changed and `total` added.
/// Fields are written in declaration order.
const Output = struct {
    id: i64,
    name: []const u8,
    score: i64,
    tags: []const []const u8,
    address: Address,
    history: []const Entry,
    total: i64,
};

fn fnv1a(hash: u32, data: []const u8) u32 {
    var h = hash;
    for (data) |b| h = (h ^ b) *% fnv_prime;
    return h;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) return error.MissingArgument;
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .unlimited);
    defer gpa.free(text);
    const reps = try std.fmt.parseInt(u64, args[2], 10);

    var records_n: i64 = 0;
    var active_n: i64 = 0;
    var score_sum: i64 = 0;
    var tags_n: i64 = 0;
    var history_n: i64 = 0;
    var amount_sum: i64 = 0;
    var output_bytes: i64 = 0;
    var hash = fnv_offset;

    var rep: u64 = 0;
    while (rep < reps) : (rep += 1) {
        const parsed = try std.json.parseFromSlice([]const Record, gpa, text, .{});
        defer parsed.deinit();

        var kept: std.ArrayList(Output) = .empty;
        defer kept.deinit(gpa);
        for (parsed.value) |r| {
            var total: i64 = 0;
            for (r.history) |e| total += e.amount;
            const n_tags: i64 = @intCast(r.tags.len);
            records_n += 1;
            score_sum += r.score;
            tags_n += n_tags;
            history_n += @intCast(r.history.len);
            amount_sum += total;
            if (r.active) {
                active_n += 1;
                try kept.append(gpa, .{
                    .id = r.id,
                    .name = r.name,
                    .score = r.score + 100 * n_tags,
                    .tags = r.tags,
                    .address = r.address,
                    .history = r.history,
                    .total = total,
                });
            }
        }

        const out = try std.json.Stringify.valueAlloc(gpa, kept.items, .{});
        defer gpa.free(out);
        output_bytes += @intCast(out.len);
        if (rep == reps - 1) hash = fnv1a(fnv_offset, out);
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("records {d}\n", .{records_n});
    try stdout.print("active {d}\n", .{active_n});
    try stdout.print("score_sum {d}\n", .{score_sum});
    try stdout.print("tags {d}\n", .{tags_n});
    try stdout.print("history {d}\n", .{history_n});
    try stdout.print("amount_sum {d}\n", .{amount_sum});
    try stdout.print("output_bytes {d}\n", .{output_bytes});
    try stdout.print("output_fnv1a {d}\n", .{hash});
    try stdout.flush();
}
