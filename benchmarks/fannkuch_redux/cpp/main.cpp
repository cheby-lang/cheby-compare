// Fannkuch-redux: flips over every permutation of 0..n, in the order the counting algorithm
// generates them. Prints the alternating checksum and the maximum flip count.

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <numeric>
#include <string>
#include <utility>
#include <vector>

namespace {

// Returns (checksum, max_flips) over all permutations of 0..n, n >= 1.
std::pair<std::int64_t, std::int64_t> fannkuch(int n) {
    std::vector<int> perm1(n);
    std::iota(perm1.begin(), perm1.end(), 0);
    std::vector<int> perm(n);
    std::vector<int> count(n);
    std::int64_t max_flips = 0;
    std::int64_t checksum = 0;
    std::int64_t perm_index = 0;
    int r = n;
    while (true) {
        while (r != 1) {
            count[r - 1] = r;
            --r;
        }

        std::copy(perm1.begin(), perm1.end(), perm.begin());
        std::int64_t flips = 0;
        int k = perm[0];
        while (k != 0) {
            std::reverse(perm.begin(), perm.begin() + k + 1);
            ++flips;
            k = perm[0];
        }
        max_flips = std::max(max_flips, flips);
        checksum += perm_index % 2 == 0 ? flips : -flips;

        while (true) {
            if (r == n) {
                return {checksum, max_flips};
            }
            std::rotate(perm1.begin(), perm1.begin() + 1, perm1.begin() + r + 1);
            --count[r];
            if (count[r] > 0) {
                break;
            }
            ++r;
        }
        ++perm_index;
    }
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main N\n";
        return 1;
    }
    const int n = std::stoi(argv[1]);
    const auto [checksum, max_flips] = fannkuch(std::max(n, 1));
    std::cout << checksum << '\n';
    std::cout << "Pfannkuchen(" << n << ") = " << max_flips << '\n';
}
