// Fannkuch-redux: flips over every permutation of 0..n, in the order the
// counting algorithm generates them. Prints the alternating checksum and the
// maximum flip count.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"

// Returns (checksum, max_flips) over all permutations of 0..n, n >= 1.
fannkuch :: proc(n: int) -> (checksum: int, max_flips: int) {
	perm1 := make([]int, n)
	defer delete(perm1)
	perm := make([]int, n)
	defer delete(perm)
	count := make([]int, n)
	defer delete(count)
	for &p, i in perm1 {
		p = i
	}
	perm_index := 0
	r := n
	for {
		for r != 1 {
			count[r - 1] = r
			r -= 1
		}

		copy(perm, perm1)
		flips := 0
		k := perm[0]
		for k != 0 {
			slice.reverse(perm[:k + 1])
			flips += 1
			k = perm[0]
		}
		max_flips = max(max_flips, flips)
		if perm_index % 2 == 0 {
			checksum += flips
		} else {
			checksum -= flips
		}

		for {
			if r == n {
				return
			}
			first := perm1[0]
			for i in 0 ..< r {
				perm1[i] = perm1[i + 1]
			}
			perm1[r] = first
			count[r] -= 1
			if count[r] > 0 {
				break
			}
			r += 1
		}
		perm_index += 1
	}
}

main :: proc() {
	if len(os.args) < 2 {
		os.exit(2)
	}
	n, ok := strconv.parse_int(os.args[1])
	if !ok || n < 0 {
		os.exit(2)
	}
	checksum, max_flips := fannkuch(max(n, 1))
	fmt.println(checksum)
	fmt.printf("Pfannkuchen(%d) = %d\n", n, max_flips)
}
