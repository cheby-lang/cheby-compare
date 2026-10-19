// spawn_many: spawn `n` short tasks in batches of BATCH, join each batch and print the sum.
// Each task is one std::jthread, an OS thread, that writes only its own slot of the batch's
// result vector. Every thread is joined before the batch is summed.

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

constexpr std::int64_t BATCH = 1000;
constexpr int ROUNDS = 10;
constexpr std::int64_t MODULUS = 2147483647;
constexpr std::int64_t MULTIPLIER = 48271;

// The value of the task with this index: ROUNDS steps of the MINSTD generator from index + 1.
std::int64_t work(std::int64_t index) {
    std::int64_t x = index + 1;
    for (int r = 0; r < ROUNDS; ++r) {
        x = x * MULTIPLIER % MODULUS;
    }
    return x;
}

// Spawns one task per index in [start, start + count), joins them all and returns their sum.
std::int64_t spawn_and_join(std::int64_t start, std::int64_t count) {
    std::vector<std::int64_t> results(count);
    {
        std::vector<std::jthread> threads;
        threads.reserve(count);
        for (std::int64_t j = 0; j < count; ++j) {
            threads.emplace_back([&results, start, j] { results[j] = work(start + j); });
        }
    }  // each std::jthread joins its thread here, when the vector is destroyed
    std::int64_t sum = 0;
    for (std::int64_t value : results) {
        sum += value;
    }
    return sum;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main <n>\n";
        return 1;
    }
    std::int64_t n = std::stoll(argv[1]);
    std::int64_t sum = 0;
    for (std::int64_t start = 0; start < n; start += BATCH) {
        sum += spawn_and_join(start, std::min(BATCH, n - start));
    }
    std::cout << "tasks: " << n << '\n' << "sum: " << sum << '\n';
}
