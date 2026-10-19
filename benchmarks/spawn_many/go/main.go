// spawn_many: spawn n short goroutines in batches of 1000, join each batch with a
// sync.WaitGroup and print the sum of the results.
package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
)

const (
	batch      = 1000
	rounds     = 10
	modulus    = 2147483647 // 2^31 - 1
	multiplier = 48271      // the MINSTD generator
)

// work is the value of the task with this index: rounds steps of MINSTD from index + 1.
func work(index int64) int64 {
	x := index + 1
	for range rounds {
		x = x * multiplier % modulus
	}
	return x
}

// spawnAndJoin starts one goroutine per index in start..start+count-1, waits for all of them
// and returns the sum of their results. Goroutine j writes only slot j of the result slice.
func spawnAndJoin(start, count int64) int64 {
	results := make([]int64, count)
	var wg sync.WaitGroup
	for j := range count {
		wg.Go(func() { results[j] = work(start + j) })
	}
	wg.Wait()
	var sum int64
	for _, r := range results {
		sum += r
	}
	return sum
}

func main() {
	n, err := strconv.ParseInt(os.Args[1], 10, 64)
	if err != nil || n < 0 {
		fmt.Fprintln(os.Stderr, "usage: main <n>, n a non-negative integer")
		os.Exit(2)
	}
	var sum int64
	for start := int64(0); start < n; start += batch {
		sum += spawnAndJoin(start, min(batch, n-start))
	}
	fmt.Printf("tasks: %d\n", n)
	fmt.Printf("sum: %d\n", sum)
}
