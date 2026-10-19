// word_freq: counts the words of a file and prints the 20 most frequent.
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

TOP :: 20

Entry :: struct {
	word:  string,
	count: int,
}

main :: proc() {
	data, err := os.read_entire_file(os.args[1], context.allocator)
	if err != nil {
		fmt.panicf("cannot read %s: %v", os.args[1], err)
	}
	text := string(data)

	// Word keys are slices into the file buffer.
	counts: map[string]int
	total := 0
	for word in strings.fields_iterator(&text) {
		counts[word] += 1
		total += 1
	}

	ranked := make([dynamic]Entry, 0, len(counts))
	for word, count in counts {
		append(&ranked, Entry{word, count})
	}
	slice.sort_by(ranked[:], proc(a, b: Entry) -> bool {
		if a.count != b.count {
			return a.count > b.count
		}
		return a.word < b.word
	})

	fmt.printfln("total %d", total)
	fmt.printfln("distinct %d", len(counts))
	for e in ranked[:min(TOP, len(ranked))] {
		fmt.printfln("%d %s", e.count, e.word)
	}
}
