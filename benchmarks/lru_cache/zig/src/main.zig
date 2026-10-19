//! LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
//!
//! The cache is an `AutoHashMap` from key to slot plus a doubly linked list of slots kept in an
//! `ArrayList`, linked by index. The head is the least recently used entry, the tail the most
//! recent.

const std = @import("std");

const modulus: u64 = 1_000_000_007;
const lehmer_m: u64 = 2_147_483_647;
const lehmer_a: u64 = 48_271;
const seed: u64 = 42;
const hot_percent: u64 = 80;
const key_space_factor: u64 = 16;
const none: u32 = std.math.maxInt(u32);

const Node = struct {
    key: u64,
    value: u64,
    prev: u32,
    next: u32,
};

const Lru = struct {
    capacity: u32,
    index: std.AutoHashMap(u64, u32),
    nodes: std.ArrayList(Node),
    head: u32 = none,
    tail: u32 = none,
    /// Removals since the last rehash. The map leaves a tombstone for every removed key and
    /// never rehashes at a constant size, so it is rehashed once every `capacity` removals.
    removals: u32 = 0,

    fn init(gpa: std.mem.Allocator, capacity: u32) !Lru {
        var index: std.AutoHashMap(u64, u32) = .init(gpa);
        try index.ensureTotalCapacity(capacity);
        return .{
            .capacity = capacity,
            .index = index,
            .nodes = try .initCapacity(gpa, capacity),
        };
    }

    fn deinit(self: *Lru, gpa: std.mem.Allocator) void {
        self.index.deinit();
        self.nodes.deinit(gpa);
    }

    fn unlink(self: *Lru, slot: u32) void {
        const node = self.nodes.items[slot];
        if (node.prev == none) self.head = node.next else self.nodes.items[node.prev].next = node.next;
        if (node.next == none) self.tail = node.prev else self.nodes.items[node.next].prev = node.prev;
    }

    fn pushBack(self: *Lru, slot: u32) void {
        self.nodes.items[slot].prev = self.tail;
        self.nodes.items[slot].next = none;
        if (self.tail == none) self.head = slot else self.nodes.items[self.tail].next = slot;
        self.tail = slot;
    }

    /// Returns the value of `key` and makes it the most recent, or null on a miss.
    fn get(self: *Lru, key: u64) ?u64 {
        const slot = self.index.get(key) orelse return null;
        if (slot != self.tail) {
            self.unlink(slot);
            self.pushBack(slot);
        }
        return self.nodes.items[slot].value;
    }

    /// Inserts a key that is not present, evicting the least recent entry when full.
    fn insert(self: *Lru, key: u64, value: u64) !void {
        var slot: u32 = undefined;
        if (self.nodes.items.len < self.capacity) {
            slot = @intCast(self.nodes.items.len);
            self.nodes.appendAssumeCapacity(.{ .key = key, .value = value, .prev = none, .next = none });
        } else {
            slot = self.head;
            self.unlink(slot);
            _ = self.index.remove(self.nodes.items[slot].key);
            self.removals += 1;
            if (self.removals == self.capacity) {
                self.index.rehash();
                self.removals = 0;
            }
            self.nodes.items[slot].key = key;
            self.nodes.items[slot].value = value;
        }
        self.pushBack(slot);
        try self.index.putNoClobber(key, slot);
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) return error.MissingArgument;
    const capacity = try std.fmt.parseInt(u32, args[1], 10);
    const ops = try std.fmt.parseInt(u64, args[2], 10);
    const hot: u64 = capacity;
    const cold: u64 = hot * (key_space_factor - 1);

    var cache: Lru = try .init(gpa, capacity);
    defer cache.deinit(gpa);
    var hits: u64 = 0;
    var misses: u64 = 0;
    var values: u64 = 0;
    var state = seed;
    var i: u64 = 0;
    while (i < ops) : (i += 1) {
        state = state * lehmer_a % lehmer_m;
        const draw = state / 100;
        const key = if (state % 100 < hot_percent) draw % hot else hot + draw % cold;
        if (cache.get(key)) |value| {
            hits += 1;
            values = (values + value) % modulus;
        } else {
            try cache.insert(key, key * 2 + 1);
            misses += 1;
        }
    }

    var checksum: u64 = 0;
    var position: u64 = 1;
    var slot = cache.head;
    while (slot != none) : (slot = cache.nodes.items[slot].next) {
        checksum = (checksum + position * cache.nodes.items[slot].key) % modulus;
        position += 1;
    }

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("hits {d}\n", .{hits});
    try stdout.print("misses {d}\n", .{misses});
    try stdout.print("values {d}\n", .{values});
    try stdout.print("checksum {d}\n", .{checksum});
    try stdout.flush();
}
