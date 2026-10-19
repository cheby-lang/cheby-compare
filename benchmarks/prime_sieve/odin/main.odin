// prime_sieve: the concurrent prime sieve, one OS thread per stage, connected by unbuffered
// channels from core:sync/chan.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:sync/chan"
import "core:thread"

// Sends 2, 3, 4 and so on until the channel is closed.
generate :: proc(output: chan.Chan(i64, .Send)) {
	for i: i64 = 2; chan.send(output, i); i += 1 {}
}

// Passes on the numbers from `input` that `prime` does not divide, until a channel is closed.
filter :: proc(input: chan.Chan(i64, .Recv), output: chan.Chan(i64, .Send), prime: i64) {
	for {
		m := chan.recv(input) or_break
		if m % prime != 0 && !chan.send(output, m) {
			return
		}
	}
}

main :: proc() {
	n, parsed := strconv.parse_i64(os.args[1])
	assert(parsed && n >= 0, "n must be a non-negative integer")

	// The threads are never joined and the channels never freed: returning from `main` ends the
	// process with the stages still blocked (SPEC, "Shut down", option 1).
	ch, _ := chan.create(chan.Chan(i64), context.allocator)
	thread.create_and_start_with_poly_data(chan.as_send(ch), generate)

	last: i64 = 0
	sum: i64 = 0
	for _ in 0 ..< n {
		prime, ok := chan.recv(ch)
		assert(ok, "the generator never stops")
		last = prime
		sum += prime
		next, _ := chan.create(chan.Chan(i64), context.allocator)
		thread.create_and_start_with_poly_data3(chan.as_recv(ch), chan.as_send(next), prime, filter)
		ch = next
	}

	fmt.printfln("primes: %d", n)
	fmt.printfln("last: %d", last)
	fmt.printfln("sum: %d", sum)
}
