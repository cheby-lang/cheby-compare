// Word frequency: reads a text file, counts its words in a map and prints the most frequent ones.
package main

import (
	"bufio"
	"cmp"
	"fmt"
	"os"
	"slices"
	"strings"
)

type entry struct {
	word  string
	count int
}

func main() {
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	counts := make(map[string]int)
	total := 0
	for word := range strings.FieldsSeq(string(data)) {
		counts[word]++
		total++
	}

	entries := make([]entry, 0, len(counts))
	for word, count := range counts {
		entries = append(entries, entry{word, count})
	}
	slices.SortFunc(entries, func(a, b entry) int {
		if c := cmp.Compare(b.count, a.count); c != 0 {
			return c
		}
		return strings.Compare(a.word, b.word)
	})

	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	fmt.Fprintf(w, "total %d\n", total)
	fmt.Fprintf(w, "distinct %d\n", len(counts))
	for _, e := range entries[:min(20, len(entries))] {
		fmt.Fprintf(w, "%d %s\n", e.count, e.word)
	}
}
