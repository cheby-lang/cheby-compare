// Spectral norm: the benchmarks-game power method on the matrix
// A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.
package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
)

// a is the matrix entry A(i, j).
func a(i, j int) float64 {
	return 1.0 / float64((i+j)*(i+j+1)/2+i+1)
}

// timesA writes A times x into out.
func timesA(x, out []float64) {
	for i := range out {
		sum := 0.0
		for j, xj := range x {
			sum += a(i, j) * xj
		}
		out[i] = sum
	}
}

// timesAt writes A transposed times x into out.
func timesAt(x, out []float64) {
	for i := range out {
		sum := 0.0
		for j, xj := range x {
			sum += a(j, i) * xj
		}
		out[i] = sum
	}
}

// timesAtA writes A transposed times A times x into out, using tmp.
func timesAtA(x, tmp, out []float64) {
	timesA(x, tmp)
	timesAt(tmp, out)
}

func dot(x, y []float64) float64 {
	sum := 0.0
	for i := range x {
		sum += x[i] * y[i]
	}
	return sum
}

func main() {
	n, err := strconv.Atoi(os.Args[1])
	if err != nil || n < 0 {
		fmt.Fprintln(os.Stderr, "usage: main N")
		os.Exit(2)
	}
	u := make([]float64, n)
	for i := range u {
		u[i] = 1.0
	}
	v := make([]float64, n)
	tmp := make([]float64, n)
	for range 10 {
		timesAtA(u, tmp, v)
		timesAtA(v, tmp, u)
	}
	vBv := dot(u, v)
	vv := dot(v, v)
	result := int64(0)
	if vv != 0.0 {
		result = int64(math.Round(math.Sqrt(vBv/vv) * 1e9))
	}
	fmt.Println(result)
}
