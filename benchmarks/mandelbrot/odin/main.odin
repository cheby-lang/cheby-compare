// Mandelbrot set on an N x N grid: count the points inside, sum the
// iterations, and checksum the positions of the inside points.
package main

import "core:fmt"
import "core:os"
import "core:strconv"

MAX_ITER :: 50

// The number of iterations before the point (cr, ci) escapes, or MAX_ITER.
escape_time :: proc(cr, ci: f64) -> int {
	zr, zi := 0.0, 0.0
	i := 0
	for i < MAX_ITER {
		zr2 := zr * zr
		zi2 := zi * zi
		if zr2 + zi2 > 4.0 {
			break
		}
		zi = 2.0 * zr * zi + ci
		zr = zr2 - zi2 + cr
		i += 1
	}
	return i
}

main :: proc() {
	if len(os.args) < 2 {
		os.exit(2)
	}
	n, ok := strconv.parse_int(os.args[1])
	if !ok || n < 0 {
		os.exit(2)
	}
	nf := f64(n)
	inside, iterations, checksum: i64
	for y in 0 ..< n {
		ci := 2.0 * f64(y) / nf - 1.0
		for x in 0 ..< n {
			cr := 2.0 * f64(x) / nf - 1.5
			i := escape_time(cr, ci)
			iterations += i64(i)
			if i == MAX_ITER {
				inside += 1
				checksum += i64(y * n + x)
			}
		}
	}
	fmt.printf("inside %d\n", inside)
	fmt.printf("iterations %d\n", iterations)
	fmt.printf("checksum %d\n", checksum % (1 << 32))
}
