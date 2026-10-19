# lru_cache: a capacity-bounded LRU cache under a skewed pseudo-random key stream.
#
# The cache is a Table from key to slot plus a doubly linked list of slots kept in a seq, linked
# by index. The head is the least recently used entry, the tail the most recent.

import std/[os, strutils, tables]

const
  Modulus = 1_000_000_007
  LehmerM = 2_147_483_647
  LehmerA = 48_271
  Seed = 42
  HotPercent = 80
  KeySpaceFactor = 16
  Nil = -1

type
  Node = object
    key, value: int
    prev, next: int

  Lru = object
    capacity: int
    index: Table[int, int]
    nodes: seq[Node]
    head, tail: int

proc initLru(capacity: int): Lru =
  Lru(capacity: capacity, index: initTable[int, int](capacity),
      nodes: newSeqOfCap[Node](capacity), head: Nil, tail: Nil)

proc unlink(c: var Lru, slot: int) =
  let (prev, next) = (c.nodes[slot].prev, c.nodes[slot].next)
  if prev == Nil: c.head = next else: c.nodes[prev].next = next
  if next == Nil: c.tail = prev else: c.nodes[next].prev = prev

proc pushBack(c: var Lru, slot: int) =
  c.nodes[slot].prev = c.tail
  c.nodes[slot].next = Nil
  if c.tail == Nil: c.head = slot else: c.nodes[c.tail].next = slot
  c.tail = slot

proc get(c: var Lru, key: int, value: var int): bool =
  ## Finds `key`, makes it the most recent and stores its value; false on a miss.
  let slot = c.index.getOrDefault(key, Nil)
  if slot == Nil:
    return false
  if slot != c.tail:
    c.unlink(slot)
    c.pushBack(slot)
  value = c.nodes[slot].value
  true

proc insert(c: var Lru, key, value: int) =
  ## Inserts a key that is not present, evicting the least recent entry when full.
  var slot: int
  if c.nodes.len < c.capacity:
    c.nodes.add(Node(key: key, value: value, prev: Nil, next: Nil))
    slot = c.nodes.high
  else:
    slot = c.head
    c.unlink(slot)
    c.index.del(c.nodes[slot].key)
    c.nodes[slot].key = key
    c.nodes[slot].value = value
  c.pushBack(slot)
  c.index[key] = slot

proc main() =
  let capacity = parseInt(paramStr(1))
  let ops = parseInt(paramStr(2))
  let hot = capacity
  let cold = capacity * (KeySpaceFactor - 1)

  var cache = initLru(capacity)
  var hits, misses, values = 0
  var state = Seed
  for _ in 0 ..< ops:
    state = state * LehmerA mod LehmerM
    let draw = state div 100
    let key =
      if state mod 100 < HotPercent: draw mod hot
      else: hot + draw mod cold
    var value: int
    if cache.get(key, value):
      inc hits
      values = (values + value) mod Modulus
    else:
      cache.insert(key, key * 2 + 1)
      inc misses

  var checksum = 0
  var position = 1
  var slot = cache.head
  while slot != Nil:
    checksum = (checksum + position * cache.nodes[slot].key) mod Modulus
    inc position
    slot = cache.nodes[slot].next

  stdout.write("hits " & $hits & "\nmisses " & $misses & "\nvalues " & $values &
    "\nchecksum " & $checksum & "\n")

main()
