// prime_sieve: the concurrent prime sieve, one goroutine per stage, connected by unbuffered
// channels. Prints n, the n-th prime and the sum of the first n primes.
package main

import (
	"fmt"
	"os"
	"strconv"
)

// generate sends 2, 3, 4 and so on to out, forever.
func generate(out chan<- int) {
	for i := 2; ; i++ {
		out <- i
	}
}

// filter passes on the numbers from in that prime does not divide, forever.
func filter(in <-chan int, out chan<- int, prime int) {
	for {
		m := <-in
		if m%prime != 0 {
			out <- m
		}
	}
}

func main() {
	n, err := strconv.Atoi(os.Args[1])
	if err != nil || n < 0 {
		fmt.Fprintln(os.Stderr, "usage: main <n>, n a non-negative integer")
		os.Exit(2)
	}

	ch := make(chan int)
	go generate(ch)
	last, sum := 0, 0
	for range n {
		prime := <-ch
		last = prime
		sum += prime
		next := make(chan int)
		go filter(ch, next, prime)
		ch = next
	}

	// Returning from main ends the process with every stage still blocked (SPEC, "Shut down").
	fmt.Printf("primes: %d\n", n)
	fmt.Printf("last: %d\n", last)
	fmt.Printf("sum: %d\n", sum)
}
