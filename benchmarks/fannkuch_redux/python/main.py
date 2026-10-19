"""Fannkuch-redux: flips over every permutation of 0..n, in the order the
counting algorithm generates them. Prints the alternating checksum and the
maximum flip count."""

import sys


def fannkuch(n):
    """Return (checksum, max_flips) over all permutations of 0..n, n >= 1."""
    perm1 = list(range(n))
    perm = [0] * n
    count = [0] * n
    max_flips = 0
    checksum = 0
    perm_index = 0
    r = n
    while True:
        while r != 1:
            count[r - 1] = r
            r -= 1

        perm[:] = perm1
        flips = 0
        k = perm[0]
        while k != 0:
            perm[: k + 1] = perm[k::-1]
            flips += 1
            k = perm[0]
        if flips > max_flips:
            max_flips = flips
        checksum += flips if perm_index % 2 == 0 else -flips

        while True:
            if r == n:
                return checksum, max_flips
            perm1[: r + 1] = perm1[1 : r + 1] + perm1[:1]
            count[r] -= 1
            if count[r] > 0:
                break
            r += 1
        perm_index += 1


def main():
    n = int(sys.argv[1])
    checksum, max_flips = fannkuch(max(n, 1))
    print(checksum)
    print(f"Pfannkuchen({n}) = {max_flips}")


if __name__ == "__main__":
    main()
