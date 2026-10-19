// word_freq: counts the words of a text file and prints the most frequent ones.

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <string_view>
#include <unordered_map>
#include <utility>
#include <vector>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main <path>\n";
        return 1;
    }
    // One read of the whole file into a string sized up front.
    std::ifstream in(argv[1], std::ios::binary);
    std::string text(std::filesystem::file_size(argv[1]), '\0');
    in.read(text.data(), static_cast<std::streamsize>(text.size()));

    // Keys are views into `text`, which outlives the map.
    std::unordered_map<std::string_view, std::int64_t> counts;
    std::int64_t total = 0;
    const std::size_t n = text.size();
    std::size_t i = 0;
    while (i < n) {
        while (i < n && (text[i] == ' ' || text[i] == '\n')) ++i;
        std::size_t start = i;
        while (i < n && text[i] != ' ' && text[i] != '\n') ++i;
        if (i > start) {
            ++counts[std::string_view(text.data() + start, i - start)];
            ++total;
        }
    }

    std::vector<std::pair<std::string_view, std::int64_t>> entries(counts.begin(), counts.end());
    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    });

    std::cout << "total " << total << '\n';
    std::cout << "distinct " << counts.size() << '\n';
    const std::size_t top = std::min<std::size_t>(20, entries.size());
    for (std::size_t k = 0; k < top; ++k) {
        std::cout << entries[k].second << ' ' << entries[k].first << '\n';
    }
}
