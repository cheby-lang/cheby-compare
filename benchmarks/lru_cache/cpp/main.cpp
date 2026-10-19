// lru_cache: an LRU cache (hash map plus doubly linked list) under a skewed pseudo-random stream.

#include <cstdint>
#include <iostream>
#include <list>
#include <string>
#include <unordered_map>

namespace {

constexpr std::int64_t LEHMER_M = 2147483647;
constexpr std::int64_t LEHMER_A = 48271;
constexpr std::int64_t SEED = 42;
constexpr std::int64_t HOT_PERCENT = 80;
constexpr std::int64_t MODULUS = 1000000007;

struct Entry {
    std::int64_t key;
    std::int64_t value;
};

std::int64_t next_state(std::int64_t state) { return state * LEHMER_A % LEHMER_M; }

std::int64_t pick_key(std::int64_t state, std::int64_t hot, std::int64_t cold) {
    const std::int64_t draw = state / 100;
    if (state % 100 < HOT_PERCENT) return draw % hot;
    return hot + draw % cold;
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "usage: main <capacity> <ops>\n";
        return 1;
    }
    const std::int64_t capacity = std::stoll(argv[1]);
    const std::int64_t ops = std::stoll(argv[2]);
    const std::int64_t hot = capacity;
    const std::int64_t cold = capacity * 15;

    // Front is the least recently used entry, back the most recently used.
    std::list<Entry> order;
    std::unordered_map<std::int64_t, std::list<Entry>::iterator> index;
    index.reserve(static_cast<std::size_t>(capacity));

    std::int64_t hits = 0, misses = 0, values = 0;
    std::int64_t state = SEED;
    for (std::int64_t op = 0; op < ops; ++op) {
        state = next_state(state);
        const std::int64_t key = pick_key(state, hot, cold);
        if (auto it = index.find(key); it != index.end()) {
            const std::int64_t value = it->second->value;
            order.splice(order.end(), order, it->second);
            ++hits;
            values = (values + value) % MODULUS;
        } else {
            if (static_cast<std::int64_t>(index.size()) == capacity) {
                // Evict the least recently used entry and reuse its node for the new one.
                index.erase(order.front().key);
                order.splice(order.end(), order, order.begin());
                order.back() = Entry{key, key * 2 + 1};
            } else {
                order.push_back(Entry{key, key * 2 + 1});
            }
            index.emplace(key, std::prev(order.end()));
            ++misses;
        }
    }

    std::int64_t checksum = 0, position = 1;
    for (const Entry& e : order) {
        checksum = (checksum + position * e.key) % MODULUS;
        ++position;
    }

    std::cout << "hits " << hits << '\n';
    std::cout << "misses " << misses << '\n';
    std::cout << "values " << values << '\n';
    std::cout << "checksum " << checksum << '\n';
}
