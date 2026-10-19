// Spectral norm: the benchmarks-game power method on the matrix
// A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"

// The entry A(i, j) of the matrix.
entry :: proc(i, j: int) -> f64 {
	return 1.0 / f64((i + j) * (i + j + 1) / 2 + i + 1)
}

// Writes A times x into out.
times_a :: proc(x, out: []f64) {
	for &o, i in out {
		sum := 0.0
		for xj, j in x {
			sum += entry(i, j) * xj
		}
		o = sum
	}
}

// Writes A transposed times x into out.
times_at :: proc(x, out: []f64) {
	for &o, i in out {
		sum := 0.0
		for xj, j in x {
			sum += entry(j, i) * xj
		}
		o = sum
	}
}

// Writes A transposed times A times x into out, using tmp.
times_ata :: proc(x, tmp, out: []f64) {
	times_a(x, tmp)
	times_at(tmp, out)
}

dot :: proc(x, y: []f64) -> f64 {
	sum := 0.0
	for xi, i in x {
		sum += xi * y[i]
	}
	return sum
}

main :: proc() {
	if len(os.args) < 2 {
		os.exit(2)
	}
	n, ok := strconv.parse_int(os.args[1])
	if !ok || n < 0 {
		os.exit(2)
	}
	u := make([]f64, n)
	v := make([]f64, n)
	tmp := make([]f64, n)
	for &x in u {
		x = 1.0
	}
	for _ in 0 ..< 10 {
		times_ata(u, tmp, v)
		times_ata(v, tmp, u)
	}
	vv := dot(v, v)
	result: i64 = 0
	if vv != 0.0 {
		result = i64(math.round(math.sqrt(dot(u, v) / vv) * 1.0e9))
	}
	fmt.println(result)
}
