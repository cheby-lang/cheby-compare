"""Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum."""

import sys

MAX_ITER = 50


def main() -> None:
    n = int(sys.argv[1])
    inside = 0
    iterations = 0
    checksum = 0
    for y in range(n):
        ci = 2.0 * y / n - 1.0
        for x in range(n):
            cr = 2.0 * x / n - 1.5
            zr = 0.0
            zi = 0.0
            i = 0
            while i < MAX_ITER:
                zr2 = zr * zr
                zi2 = zi * zi
                if zr2 + zi2 > 4.0:
                    break
                zi = 2.0 * zr * zi + ci
                zr = zr2 - zi2 + cr
                i += 1
            iterations += i
            if i == MAX_ITER:
                inside += 1
                checksum += y * n + x
    print(f"inside {inside}")
    print(f"iterations {iterations}")
    print(f"checksum {checksum % 4294967296}")


main()
