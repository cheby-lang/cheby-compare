// spawn_many: spawn `n` short tasks in batches of `BATCH`, join each batch and print the sum.
// Each task is one OS thread from core:thread and writes its result into its own slot.
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:thread"

BATCH :: 1000
ROUNDS :: 10
MODULUS :: 2147483647
MULTIPLIER :: 48271

// The value of the task with this index: `ROUNDS` steps of the MINSTD generator from `index + 1`.
work :: proc(index: i64) -> i64 {
	x := index + 1
	for _ in 0 ..< ROUNDS {
		x = x * MULTIPLIER % MODULUS
	}
	return x
}

// The body of one task: computes `work(index)` into the task's own result slot.
task :: proc(index: i64, slot: ^i64) {
	slot^ = work(index)
}

// Spawns one thread per index in `start ..< start + count`, joins them all and returns their sum.
spawn_and_join :: proc(start, count: i64) -> i64 {
	results := make([]i64, count)
	defer delete(results)
	threads := make([]^thread.Thread, count)
	defer delete(threads)

	for j in 0 ..< count {
		threads[j] = thread.create_and_start_with_poly_data2(start + j, &results[j], task)
	}
	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}

	sum: i64 = 0
	for r in results {
		sum += r
	}
	return sum
}

main :: proc() {
	n, parsed := strconv.parse_i64(os.args[1])
	assert(parsed && n >= 0, "n must be a non-negative integer")

	sum: i64 = 0
	for start: i64 = 0; start < n; start += BATCH {
		sum += spawn_and_join(start, min(BATCH, n - start))
	}
	fmt.printfln("tasks: %d", n)
	fmt.printfln("sum: %d", sum)
}
