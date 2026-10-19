"""Spectral norm: the benchmarks-game power method on the matrix
A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n."""

import math
import sys


# A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1) is written out in the inner
# loops: a function call per entry costs CPython about 15%.
def times_a(x):
    n = len(x)
    out = [0.0] * n
    for i in range(n):
        total = 0.0
        for j, xj in enumerate(x):
            ij = i + j
            total += 1.0 / (ij * (ij + 1) // 2 + i + 1) * xj
        out[i] = total
    return out


def times_at(x):
    n = len(x)
    out = [0.0] * n
    for i in range(n):
        total = 0.0
        for j, xj in enumerate(x):
            ij = i + j
            total += 1.0 / (ij * (ij + 1) // 2 + j + 1) * xj
        out[i] = total
    return out


def times_ata(x):
    return times_at(times_a(x))


def dot(x, y):
    total = 0.0
    for a, b in zip(x, y):
        total += a * b
    return total


def round_half_away(x):
    """Rounds to the nearest integer, halfway cases away from zero."""
    magnitude = abs(x)
    whole = math.floor(magnitude)
    if magnitude - whole >= 0.5:
        whole += 1
    return int(whole) if x >= 0 else -int(whole)


def main():
    n = int(sys.argv[1])
    u = [1.0] * n
    v = [0.0] * n
    for _ in range(10):
        v = times_ata(u)
        u = times_ata(v)
    vv = dot(v, v)
    if vv == 0.0:
        result = 0
    else:
        result = round_half_away(math.sqrt(dot(u, v) / vv) * 1e9)
    print(result)


if __name__ == "__main__":
    main()
