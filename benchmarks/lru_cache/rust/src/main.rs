//! LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
//!
//! The cache is a `HashMap` from key to slot plus a doubly linked list of slots kept in a `Vec`,
//! linked by index. The head is the least recently used entry, the tail the most recent.

use std::collections::HashMap;
use std::env;

const MODULUS: u64 = 1_000_000_007;
const LEHMER_M: u64 = 2_147_483_647;
const LEHMER_A: u64 = 48_271;
const SEED: u64 = 42;
const HOT_PERCENT: u64 = 80;
const KEY_SPACE_FACTOR: u64 = 16;
const NONE: usize = usize::MAX;

struct Node {
    key: u64,
    value: u64,
    prev: usize,
    next: usize,
}

struct Lru {
    capacity: usize,
    index: HashMap<u64, usize>,
    nodes: Vec<Node>,
    head: usize,
    tail: usize,
}

impl Lru {
    fn new(capacity: usize) -> Self {
        Lru {
            capacity,
            index: HashMap::with_capacity(capacity),
            nodes: Vec::with_capacity(capacity),
            head: NONE,
            tail: NONE,
        }
    }

    fn unlink(&mut self, slot: usize) {
        let (prev, next) = (self.nodes[slot].prev, self.nodes[slot].next);
        match prev {
            NONE => self.head = next,
            p => self.nodes[p].next = next,
        }
        match next {
            NONE => self.tail = prev,
            n => self.nodes[n].prev = prev,
        }
    }

    fn push_back(&mut self, slot: usize) {
        self.nodes[slot].prev = self.tail;
        self.nodes[slot].next = NONE;
        match self.tail {
            NONE => self.head = slot,
            t => self.nodes[t].next = slot,
        }
        self.tail = slot;
    }

    /// Returns the value of `key` and makes it the most recent, or `None` on a miss.
    fn get(&mut self, key: u64) -> Option<u64> {
        let slot = *self.index.get(&key)?;
        if slot != self.tail {
            self.unlink(slot);
            self.push_back(slot);
        }
        Some(self.nodes[slot].value)
    }

    /// Inserts a key that is not present, evicting the least recent entry when full.
    fn insert(&mut self, key: u64, value: u64) {
        let slot = if self.nodes.len() < self.capacity {
            self.nodes.push(Node {
                key,
                value,
                prev: NONE,
                next: NONE,
            });
            self.nodes.len() - 1
        } else {
            let slot = self.head;
            self.unlink(slot);
            self.index.remove(&self.nodes[slot].key);
            self.nodes[slot].key = key;
            self.nodes[slot].value = value;
            slot
        };
        self.push_back(slot);
        self.index.insert(key, slot);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let capacity: u64 = args[1].parse().expect("capacity");
    let ops: u64 = args[2].parse().expect("ops");
    let hot = capacity;
    let cold = capacity * (KEY_SPACE_FACTOR - 1);

    let mut cache = Lru::new(capacity as usize);
    let (mut hits, mut misses, mut values) = (0u64, 0u64, 0u64);
    let mut state = SEED;
    for _ in 0..ops {
        state = state * LEHMER_A % LEHMER_M;
        let draw = state / 100;
        let key = if state % 100 < HOT_PERCENT {
            draw % hot
        } else {
            hot + draw % cold
        };
        match cache.get(key) {
            Some(value) => {
                hits += 1;
                values = (values + value) % MODULUS;
            }
            None => {
                cache.insert(key, key * 2 + 1);
                misses += 1;
            }
        }
    }

    let mut checksum = 0u64;
    let mut slot = cache.head;
    let mut position = 1u64;
    while slot != NONE {
        checksum = (checksum + position * cache.nodes[slot].key) % MODULUS;
        position += 1;
        slot = cache.nodes[slot].next;
    }

    println!("hits {hits}");
    println!("misses {misses}");
    println!("values {values}");
    println!("checksum {checksum}");
}
