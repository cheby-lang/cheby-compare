"""LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream."""

import sys
from collections import OrderedDict

MODULUS = 1_000_000_007
LEHMER_M = 2_147_483_647
LEHMER_A = 48_271
SEED = 42
HOT_PERCENT = 80
KEY_SPACE_FACTOR = 16


def main() -> None:
    capacity = int(sys.argv[1])
    ops = int(sys.argv[2])
    hot = capacity
    cold = capacity * (KEY_SPACE_FACTOR - 1)

    cache: OrderedDict[int, int] = OrderedDict()
    hits = 0
    misses = 0
    values = 0
    state = SEED
    for _ in range(ops):
        state = state * LEHMER_A % LEHMER_M
        draw = state // 100
        if state % 100 < HOT_PERCENT:
            key = draw % hot
        else:
            key = hot + draw % cold
        value = cache.get(key)
        if value is not None:
            cache.move_to_end(key)
            hits += 1
            values = (values + value) % MODULUS
        else:
            if len(cache) == capacity:
                cache.popitem(last=False)
            cache[key] = key * 2 + 1
            misses += 1

    checksum = 0
    for position, key in enumerate(cache, 1):
        checksum = (checksum + position * key) % MODULUS

    print(f"hits {hits}")
    print(f"misses {misses}")
    print(f"values {values}")
    print(f"checksum {checksum}")


if __name__ == "__main__":
    main()
