// Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.
package main

import (
	"fmt"
	"os"
	"strconv"
)

const maxIter = 50

// escapeTime returns the number of iterations before (cr, ci) escapes, or maxIter.
// The explicit float64 conversions keep Go from fusing a*b+c into an FMA, as the spec requires.
func escapeTime(cr, ci float64) int {
	zr, zi := 0.0, 0.0
	i := 0
	for i < maxIter {
		zr2 := float64(zr * zr)
		zi2 := float64(zi * zi)
		if zr2+zi2 > 4.0 {
			break
		}
		zi = float64(2.0*zr*zi) + ci
		zr = zr2 - zi2 + cr
		i++
	}
	return i
}

func main() {
	n, err := strconv.Atoi(os.Args[1])
	if err != nil || n < 0 {
		fmt.Fprintln(os.Stderr, "usage: main N")
		os.Exit(2)
	}
	nf := float64(n)
	inside, iterations, checksum := 0, 0, 0
	for y := range n {
		ci := 2.0*float64(y)/nf - 1.0
		for x := range n {
			cr := 2.0*float64(x)/nf - 1.5
			i := escapeTime(cr, ci)
			iterations += i
			if i == maxIter {
				inside++
				checksum += y*n + x
			}
		}
	}
	fmt.Println("inside", inside)
	fmt.Println("iterations", iterations)
	fmt.Println("checksum", uint64(checksum)%(1<<32))
}
