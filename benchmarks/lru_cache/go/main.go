// LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
//
// The cache is a map from key to list element plus a container/list kept in recency order:
// the front is the least recently used entry, the back the most recent.
package main

import (
	"container/list"
	"fmt"
	"os"
	"strconv"
)

const (
	modulus        = 1000000007
	lehmerM        = 2147483647
	lehmerA        = 48271
	seed           = 42
	hotPercent     = 80
	keySpaceFactor = 16
)

type entry struct {
	key, value int
}

type lru struct {
	capacity int
	index    map[int]*list.Element
	order    *list.List
}

func newLRU(capacity int) *lru {
	return &lru{
		capacity: capacity,
		index:    make(map[int]*list.Element, capacity),
		order:    list.New(),
	}
}

// get returns the value of key and makes it the most recent, or false on a miss.
func (c *lru) get(key int) (int, bool) {
	el, ok := c.index[key]
	if !ok {
		return 0, false
	}
	c.order.MoveToBack(el)
	return el.Value.(*entry).value, true
}

// insert adds a key that is not present, evicting the least recent entry when full.
func (c *lru) insert(key, value int) {
	if c.order.Len() < c.capacity {
		c.index[key] = c.order.PushBack(&entry{key, value})
		return
	}
	el := c.order.Front()
	e := el.Value.(*entry)
	delete(c.index, e.key)
	e.key, e.value = key, value
	c.order.MoveToBack(el)
	c.index[key] = el
}

func main() {
	capacity, err1 := strconv.Atoi(os.Args[1])
	ops, err2 := strconv.Atoi(os.Args[2])
	if err1 != nil || err2 != nil {
		fmt.Fprintln(os.Stderr, "usage: main <capacity> <ops>")
		os.Exit(1)
	}
	hot := capacity
	cold := capacity * (keySpaceFactor - 1)

	cache := newLRU(capacity)
	var hits, misses, values int
	state := seed
	for range ops {
		state = state * lehmerA % lehmerM
		draw := state / 100
		var key int
		if state%100 < hotPercent {
			key = draw % hot
		} else {
			key = hot + draw%cold
		}
		if value, ok := cache.get(key); ok {
			hits++
			values = (values + value) % modulus
		} else {
			cache.insert(key, key*2+1)
			misses++
		}
	}

	checksum, position := 0, 1
	for el := cache.order.Front(); el != nil; el = el.Next() {
		checksum = (checksum + position*el.Value.(*entry).key) % modulus
		position++
	}

	fmt.Printf("hits %d\n", hits)
	fmt.Printf("misses %d\n", misses)
	fmt.Printf("values %d\n", values)
	fmt.Printf("checksum %d\n", checksum)
}
