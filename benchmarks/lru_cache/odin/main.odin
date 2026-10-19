// lru_cache: a capacity-bounded LRU cache under a skewed pseudo-random key stream.
//
// The cache is a map from key to slot plus a doubly linked list of slots kept in a
// [dynamic]Node, linked by index. The head is the least recently used entry, the tail the
// most recent.
package main

import "core:fmt"
import "core:os"
import "core:strconv"

MODULUS :: 1_000_000_007
LEHMER_M :: 2_147_483_647
LEHMER_A :: 48_271
SEED :: 42
HOT_PERCENT :: 80
KEY_SPACE_FACTOR :: 16
NONE :: -1

Node :: struct {
	key:   int,
	value: int,
	prev:  int,
	next:  int,
}

Lru :: struct {
	capacity: int,
	index:    map[int]int,
	nodes:    [dynamic]Node,
	head:     int,
	tail:     int,
}

lru_make :: proc(capacity: int) -> Lru {
	return Lru {
		capacity = capacity,
		index = make(map[int]int, capacity),
		nodes = make([dynamic]Node, 0, capacity),
		head = NONE,
		tail = NONE,
	}
}

unlink :: proc(c: ^Lru, slot: int) {
	prev, next := c.nodes[slot].prev, c.nodes[slot].next
	if prev == NONE {
		c.head = next
	} else {
		c.nodes[prev].next = next
	}
	if next == NONE {
		c.tail = prev
	} else {
		c.nodes[next].prev = prev
	}
}

push_back :: proc(c: ^Lru, slot: int) {
	c.nodes[slot].prev = c.tail
	c.nodes[slot].next = NONE
	if c.tail == NONE {
		c.head = slot
	} else {
		c.nodes[c.tail].next = slot
	}
	c.tail = slot
}

// Returns the value of `key` and makes it the most recent, or false on a miss.
lru_get :: proc(c: ^Lru, key: int) -> (value: int, ok: bool) {
	slot := c.index[key] or_return
	if slot != c.tail {
		unlink(c, slot)
		push_back(c, slot)
	}
	return c.nodes[slot].value, true
}

// Inserts a key that is not present, evicting the least recent entry when full.
lru_insert :: proc(c: ^Lru, key, value: int) {
	slot: int
	if len(c.nodes) < c.capacity {
		append(&c.nodes, Node{key = key, value = value, prev = NONE, next = NONE})
		slot = len(c.nodes) - 1
	} else {
		slot = c.head
		unlink(c, slot)
		delete_key(&c.index, c.nodes[slot].key)
		c.nodes[slot].key = key
		c.nodes[slot].value = value
	}
	push_back(c, slot)
	c.index[key] = slot
}

main :: proc() {
	capacity, ok1 := strconv.parse_int(os.args[1])
	ops, ok2 := strconv.parse_int(os.args[2])
	if !ok1 || !ok2 || capacity < 1 || ops < 0 {
		panic("usage: main CAPACITY OPS")
	}
	hot := capacity
	cold := capacity * (KEY_SPACE_FACTOR - 1)

	cache := lru_make(capacity)
	hits, misses, values: int
	state := SEED
	for _ in 0 ..< ops {
		state = state * LEHMER_A % LEHMER_M
		draw := state / 100
		key := state % 100 < HOT_PERCENT ? draw % hot : hot + draw % cold
		if value, hit := lru_get(&cache, key); hit {
			hits += 1
			values = (values + value) % MODULUS
		} else {
			lru_insert(&cache, key, key * 2 + 1)
			misses += 1
		}
	}

	checksum := 0
	position := 1
	for slot := cache.head; slot != NONE; slot = cache.nodes[slot].next {
		checksum = (checksum + position * cache.nodes[slot].key) % MODULUS
		position += 1
	}

	fmt.printf("hits %d\n", hits)
	fmt.printf("misses %d\n", misses)
	fmt.printf("values %d\n", values)
	fmt.printf("checksum %d\n", checksum)
}
