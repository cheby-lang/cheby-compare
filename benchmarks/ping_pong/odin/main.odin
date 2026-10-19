// ping_pong: two OS threads exchange `n` messages over two unbuffered channels.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:sync/chan"
import "core:thread"

// Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
echo :: proc(n: i64, ping: chan.Chan(i64, .Recv), pong: chan.Chan(i64, .Send)) {
	for _ in 0 ..< n {
		x, ok := chan.recv(ping)
		assert(ok, "ping closed")
		sent := chan.send(pong, x + 1)
		assert(sent, "pong closed")
	}
}

main :: proc() {
	n, parsed := strconv.parse_i64(os.args[1])
	assert(parsed && n >= 0, "n must be a non-negative integer")

	ping, _ := chan.create(chan.Chan(i64), context.allocator)
	pong, _ := chan.create(chan.Chan(i64), context.allocator)
	defer chan.destroy(ping)
	defer chan.destroy(pong)

	b := thread.create_and_start_with_poly_data3(n, chan.as_recv(ping), chan.as_send(pong), echo)

	sum: i64 = 0
	for i in 1 ..= n {
		sent := chan.send(ping, i)
		assert(sent, "ping closed")
		x, ok := chan.recv(pong)
		assert(ok, "pong closed")
		sum += x
	}
	thread.join(b)
	thread.destroy(b)

	fmt.println(n)
	fmt.println(sum)
}
