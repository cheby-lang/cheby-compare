// LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
//
// The cache is a Map from key to slot plus a doubly linked list of slots in typed arrays,
// linked by index. The head is the least recently used entry, the tail the most recent.
// Every value stays below 2^47, so plain numbers (doubles) are exact.

const MODULUS = 1000000007;
const LEHMER_M = 2147483647;
const LEHMER_A = 48271;
const SEED = 42;
const HOT_PERCENT = 80;
const KEY_SPACE_FACTOR = 16;
const NONE = -1;

class Lru {
  readonly capacity: number;
  readonly index: Map<number, number>;
  readonly keys: Float64Array;
  readonly values: Float64Array;
  readonly prev: Int32Array;
  readonly next: Int32Array;
  size = 0;
  head = NONE;
  tail = NONE;

  constructor(capacity: number) {
    this.capacity = capacity;
    this.index = new Map();
    this.keys = new Float64Array(capacity);
    this.values = new Float64Array(capacity);
    this.prev = new Int32Array(capacity);
    this.next = new Int32Array(capacity);
  }

  private unlink(slot: number): void {
    const p = this.prev[slot];
    const n = this.next[slot];
    if (p === NONE) this.head = n;
    else this.next[p] = n;
    if (n === NONE) this.tail = p;
    else this.prev[n] = p;
  }

  private pushBack(slot: number): void {
    this.prev[slot] = this.tail;
    this.next[slot] = NONE;
    if (this.tail === NONE) this.head = slot;
    else this.next[this.tail] = slot;
    this.tail = slot;
  }

  /** Returns the value of `key` and makes it the most recent, or undefined on a miss. */
  get(key: number): number | undefined {
    const slot = this.index.get(key);
    if (slot === undefined) return undefined;
    if (slot !== this.tail) {
      this.unlink(slot);
      this.pushBack(slot);
    }
    return this.values[slot];
  }

  /** Inserts a key that is not present, evicting the least recent entry when full. */
  insert(key: number, value: number): void {
    let slot: number;
    if (this.size < this.capacity) {
      slot = this.size++;
    } else {
      slot = this.head;
      this.unlink(slot);
      this.index.delete(this.keys[slot]);
    }
    this.keys[slot] = key;
    this.values[slot] = value;
    this.pushBack(slot);
    this.index.set(key, slot);
  }
}

function main(capacity: number, ops: number): void {
  const hot = capacity;
  const cold = capacity * (KEY_SPACE_FACTOR - 1);

  const cache = new Lru(capacity);
  let hits = 0;
  let misses = 0;
  let values = 0;
  let state = SEED;
  for (let i = 0; i < ops; i++) {
    state = (state * LEHMER_A) % LEHMER_M;
    const draw = Math.floor(state / 100);
    const key = state % 100 < HOT_PERCENT ? draw % hot : hot + (draw % cold);
    const value = cache.get(key);
    if (value !== undefined) {
      hits++;
      values = (values + value) % MODULUS;
    } else {
      cache.insert(key, key * 2 + 1);
      misses++;
    }
  }

  let checksum = 0;
  let position = 1;
  for (let slot = cache.head; slot !== NONE; slot = cache.next[slot]) {
    checksum = (checksum + position * cache.keys[slot]) % MODULUS;
    position++;
  }

  process.stdout.write(
    `hits ${hits}\nmisses ${misses}\nvalues ${values}\nchecksum ${checksum}\n`,
  );
}

main(Number.parseInt(process.argv[2], 10), Number.parseInt(process.argv[3], 10));
