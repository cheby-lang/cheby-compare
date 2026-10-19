// ping_pong: the main goroutine and one spawned goroutine pass a number back and forth n times
// over two unbuffered channels, then print n and the sum of the answers.
package main

import (
	"fmt"
	"os"
	"strconv"
	"sync"
)

// echo is task B: it answers each of the n values from ping with the value plus one on pong.
func echo(n int64, ping <-chan int64, pong chan<- int64) {
	for range n {
		x := <-ping
		pong <- x + 1
	}
}

func main() {
	n, err := strconv.ParseInt(os.Args[1], 10, 64)
	if err != nil || n < 0 {
		fmt.Fprintln(os.Stderr, "usage: main <n>, n a non-negative integer")
		os.Exit(2)
	}

	ping := make(chan int64)
	pong := make(chan int64)
	var wg sync.WaitGroup
	wg.Go(func() { echo(n, ping, pong) })

	// Task A is the main goroutine.
	var sum int64
	for i := int64(1); i <= n; i++ {
		ping <- i
		sum += <-pong
	}
	wg.Wait()

	fmt.Println(n)
	fmt.Println(sum)
}
