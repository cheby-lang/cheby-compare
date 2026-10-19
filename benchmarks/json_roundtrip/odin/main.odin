// json_roundtrip: parses a JSON array of records, transforms it and serializes it again.
package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strconv"

FNV_OFFSET :: u32(2166136261)
FNV_PRIME :: u32(16777619)

Address :: struct {
	street: string,
	city:   string,
	zip:    i64,
}

Entry :: struct {
	day:    i64,
	amount: i64,
}

Record :: struct {
	id:      i64,
	name:    string,
	active:  bool,
	score:   i64,
	tags:    []string,
	address: Address,
	history: []Entry,
}

// A kept record as it is written: `active` is gone, `score` changed and `total` added.
// It shares its strings and slices with the parsed record.
Output :: struct {
	id:      i64,
	name:    string,
	score:   i64,
	tags:    []string,
	address: Address,
	history: []Entry,
	total:   i64,
}

destroy_records :: proc(records: []Record) {
	for r in records {
		delete(r.name)
		for t in r.tags {
			delete(t)
		}
		delete(r.tags)
		delete(r.address.street)
		delete(r.address.city)
		delete(r.history)
	}
	delete(records)
}

main :: proc() {
	data, err := os.read_entire_file(os.args[1], context.allocator)
	if err != nil {
		fmt.panicf("cannot read %s: %v", os.args[1], err)
	}
	reps, ok := strconv.parse_int(os.args[2])
	if !ok || reps < 0 {
		panic("reps must be a non-negative integer")
	}

	records_n, active_n, score_sum, tags_n: i64
	history_n, amount_sum, output_bytes: i64
	h := FNV_OFFSET
	for rep in 0 ..< reps {
		records: []Record
		if uerr := json.unmarshal(data, &records); uerr != nil {
			fmt.panicf("invalid input: %v", uerr)
		}
		kept: [dynamic]Output
		for r in records {
			total: i64
			for e in r.history {
				total += e.amount
			}
			records_n += 1
			score_sum += r.score
			tags_n += i64(len(r.tags))
			history_n += i64(len(r.history))
			amount_sum += total
			if r.active {
				active_n += 1
				append(&kept, Output {
					id      = r.id,
					name    = r.name,
					score   = r.score + 100 * i64(len(r.tags)),
					tags    = r.tags,
					address = r.address,
					history = r.history,
					total   = total,
				})
			}
		}
		out, merr := json.marshal(kept)
		if merr != nil {
			fmt.panicf("cannot serialize: %v", merr)
		}
		output_bytes += i64(len(out))
		if rep == reps - 1 {
			for b in out {
				h = (h ~ u32(b)) * FNV_PRIME
			}
		}
		delete(out)
		delete(kept)
		destroy_records(records)
	}

	fmt.printf("records %d\n", records_n)
	fmt.printf("active %d\n", active_n)
	fmt.printf("score_sum %d\n", score_sum)
	fmt.printf("tags %d\n", tags_n)
	fmt.printf("history %d\n", history_n)
	fmt.printf("amount_sum %d\n", amount_sum)
	fmt.printf("output_bytes %d\n", output_bytes)
	fmt.printf("output_fnv1a %d\n", h)
}
