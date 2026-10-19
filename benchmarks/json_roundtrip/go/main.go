// json_roundtrip: parses a JSON array of records, transforms it and serializes it again.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
)

const (
	fnvOffset uint32 = 2166136261
	fnvPrime  uint32 = 16777619
)

type Address struct {
	Street string `json:"street"`
	City   string `json:"city"`
	Zip    int64  `json:"zip"`
}

type Entry struct {
	Day    int64 `json:"day"`
	Amount int64 `json:"amount"`
}

type Record struct {
	ID      int64    `json:"id"`
	Name    string   `json:"name"`
	Active  bool     `json:"active"`
	Score   int64    `json:"score"`
	Tags    []string `json:"tags"`
	Address Address  `json:"address"`
	History []Entry  `json:"history"`
}

// Output is a kept record as it is written: active is gone, score changed and total added.
type Output struct {
	ID      int64    `json:"id"`
	Name    string   `json:"name"`
	Score   int64    `json:"score"`
	Tags    []string `json:"tags"`
	Address *Address `json:"address"`
	History []Entry  `json:"history"`
	Total   int64    `json:"total"`
}

func main() {
	text, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	reps, err := strconv.ParseInt(os.Args[2], 10, 64)
	if err != nil {
		fmt.Fprintln(os.Stderr, "reps must be a non-negative integer")
		os.Exit(1)
	}

	var recordsN, activeN, scoreSum, tagsN, historyN, amountSum, outputBytes int64
	h := fnvOffset
	for rep := range reps {
		var records []Record
		if err := json.Unmarshal(text, &records); err != nil {
			fmt.Fprintln(os.Stderr, "invalid input:", err)
			os.Exit(1)
		}
		kept := make([]Output, 0)
		for i := range records {
			r := &records[i]
			var total int64
			for _, e := range r.History {
				total += e.Amount
			}
			recordsN++
			scoreSum += r.Score
			tagsN += int64(len(r.Tags))
			historyN += int64(len(r.History))
			amountSum += total
			if r.Active {
				activeN++
				kept = append(kept, Output{
					ID:      r.ID,
					Name:    r.Name,
					Score:   r.Score + 100*int64(len(r.Tags)),
					Tags:    r.Tags,
					Address: &r.Address,
					History: r.History,
					Total:   total,
				})
			}
		}
		out, err := json.Marshal(kept)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		outputBytes += int64(len(out))
		if rep == reps-1 {
			for _, b := range out {
				h = (h ^ uint32(b)) * fnvPrime
			}
		}
	}

	fmt.Printf("records %d\n", recordsN)
	fmt.Printf("active %d\n", activeN)
	fmt.Printf("score_sum %d\n", scoreSum)
	fmt.Printf("tags %d\n", tagsN)
	fmt.Printf("history %d\n", historyN)
	fmt.Printf("amount_sum %d\n", amountSum)
	fmt.Printf("output_bytes %d\n", outputBytes)
	fmt.Printf("output_fnv1a %d\n", h)
}
