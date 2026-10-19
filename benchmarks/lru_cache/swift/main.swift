// LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
//
// The cache is a Dictionary from key to slot plus a doubly linked list of slots kept in an
// array of nodes, linked by index. The head is the least recently used entry, the tail the most
// recent.

let modulus = 1_000_000_007
let lehmerM = 2_147_483_647
let lehmerA = 48_271
let seed = 42
let hotPercent = 80
let keySpaceFactor = 16
let none = -1

struct Node {
  var key: Int
  var value: Int
  var prev: Int
  var next: Int
}

struct LRUCache {
  let capacity: Int
  private var index: [Int: Int]
  private(set) var nodes: [Node] = []
  private(set) var head = none
  private var tail = none

  init(capacity: Int) {
    self.capacity = capacity
    index = Dictionary(minimumCapacity: capacity)
    nodes.reserveCapacity(capacity)
  }

  private mutating func unlink(_ slot: Int) {
    let prev = nodes[slot].prev
    let next = nodes[slot].next
    if prev == none { head = next } else { nodes[prev].next = next }
    if next == none { tail = prev } else { nodes[next].prev = prev }
  }

  private mutating func pushBack(_ slot: Int) {
    nodes[slot].prev = tail
    nodes[slot].next = none
    if tail == none { head = slot } else { nodes[tail].next = slot }
    tail = slot
  }

  /// Returns the value of `key` and makes it the most recent, or nil on a miss.
  mutating func get(_ key: Int) -> Int? {
    guard let slot = index[key] else { return nil }
    if slot != tail {
      unlink(slot)
      pushBack(slot)
    }
    return nodes[slot].value
  }

  /// Inserts a key that is not present, evicting the least recent entry when full.
  mutating func insert(_ key: Int, _ value: Int) {
    let slot: Int
    if nodes.count < capacity {
      nodes.append(Node(key: key, value: value, prev: none, next: none))
      slot = nodes.count - 1
    } else {
      slot = head
      unlink(slot)
      index.removeValue(forKey: nodes[slot].key)
      nodes[slot].key = key
      nodes[slot].value = value
    }
    pushBack(slot)
    index[key] = slot
  }
}

func run(capacity: Int, ops: Int) -> String {
  let hot = capacity
  let cold = capacity * (keySpaceFactor - 1)

  var cache = LRUCache(capacity: capacity)
  var hits = 0
  var misses = 0
  var values = 0
  var state = seed
  for _ in 0..<ops {
    state = state * lehmerA % lehmerM
    let draw = state / 100
    let key = state % 100 < hotPercent ? draw % hot : hot + draw % cold
    if let value = cache.get(key) {
      hits += 1
      values = (values + value) % modulus
    } else {
      cache.insert(key, key * 2 + 1)
      misses += 1
    }
  }

  var checksum = 0
  var position = 1
  var slot = cache.head
  while slot != none {
    checksum = (checksum + position * cache.nodes[slot].key) % modulus
    position += 1
    slot = cache.nodes[slot].next
  }

  return "hits \(hits)\nmisses \(misses)\nvalues \(values)\nchecksum \(checksum)"
}

print(run(capacity: Int(CommandLine.arguments[1])!, ops: Int(CommandLine.arguments[2])!))
