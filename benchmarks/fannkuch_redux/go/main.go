// Fannkuch-redux: flips over every permutation of 0..n, in the order the counting algorithm
// generates them. Prints the alternating checksum and the maximum flip count.
package main

import (
	"fmt"
	"os"
	"slices"
	"strconv"
)

// fannkuch returns (checksum, maxFlips) over all permutations of 0..n, n >= 1.
func fannkuch(n int) (int, int) {
	perm1 := make([]int, n)
	for i := range perm1 {
		perm1[i] = i
	}
	perm := make([]int, n)
	count := make([]int, n)
	maxFlips, checksum, permIndex := 0, 0, 0
	r := n
	for {
		for r != 1 {
			count[r-1] = r
			r--
		}

		copy(perm, perm1)
		flips := 0
		for k := perm[0]; k != 0; k = perm[0] {
			slices.Reverse(perm[:k+1])
			flips++
		}
		maxFlips = max(maxFlips, flips)
		if permIndex%2 == 0 {
			checksum += flips
		} else {
			checksum -= flips
		}

		for {
			if r == n {
				return checksum, maxFlips
			}
			first := perm1[0]
			copy(perm1[:r], perm1[1:r+1])
			perm1[r] = first
			count[r]--
			if count[r] > 0 {
				break
			}
			r++
		}
		permIndex++
	}
}

func main() {
	n, err := strconv.Atoi(os.Args[1])
	if err != nil || n < 0 || n > 12 {
		fmt.Fprintln(os.Stderr, "usage: main N (0 <= N <= 12)")
		os.Exit(2)
	}
	checksum, maxFlips := fannkuch(max(n, 1))
	fmt.Println(checksum)
	fmt.Printf("Pfannkuchen(%d) = %d\n", n, maxFlips)
}
