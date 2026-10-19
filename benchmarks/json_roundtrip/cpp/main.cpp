// json_roundtrip: parses a JSON array of records, transforms it and serializes it again.

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

using json = nlohmann::ordered_json;  // keeps key order; nlohmann::json would sort the keys

namespace {

constexpr std::uint32_t FNV_OFFSET = 2166136261u;
constexpr std::uint32_t FNV_PRIME = 16777619u;

struct Address {
    std::string street;
    std::string city;
    std::int64_t zip;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Address, street, city, zip)

struct Entry {
    std::int64_t day;
    std::int64_t amount;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Entry, day, amount)

struct Record {
    std::int64_t id;
    std::string name;
    bool active;
    std::int64_t score;
    std::vector<std::string> tags;
    Address address;
    std::vector<Entry> history;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Record, id, name, active, score, tags, address, history)

// A kept record as it is written: `active` is gone, `score` changed and `total` added.
struct Output {
    std::int64_t id;
    std::string name;
    std::int64_t score;
    std::vector<std::string> tags;
    Address address;
    std::vector<Entry> history;
    std::int64_t total;
};
NLOHMANN_DEFINE_TYPE_NON_INTRUSIVE(Output, id, name, score, tags, address, history, total)

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "usage: main <path> <reps>\n";
        return 1;
    }
    // One read of the whole file into a string sized up front.
    std::ifstream in(argv[1], std::ios::binary);
    std::string text(std::filesystem::file_size(argv[1]), '\0');
    in.read(text.data(), static_cast<std::streamsize>(text.size()));
    const std::int64_t reps = std::stoll(argv[2]);

    std::int64_t records_n = 0, active_n = 0, score_sum = 0, tags_n = 0;
    std::int64_t history_n = 0, amount_sum = 0, output_bytes = 0;
    std::uint32_t hash = FNV_OFFSET;
    for (std::int64_t rep = 0; rep < reps; ++rep) {
        auto records = json::parse(text).get<std::vector<Record>>();
        std::vector<Output> kept;
        for (Record& r : records) {
            std::int64_t total = 0;
            for (const Entry& e : r.history) total += e.amount;
            const auto tags_len = static_cast<std::int64_t>(r.tags.size());
            records_n += 1;
            score_sum += r.score;
            tags_n += tags_len;
            history_n += static_cast<std::int64_t>(r.history.size());
            amount_sum += total;
            if (r.active) {
                active_n += 1;
                kept.push_back(Output{r.id, std::move(r.name), r.score + 100 * tags_len,
                                      std::move(r.tags), std::move(r.address),
                                      std::move(r.history), total});
            }
        }
        const std::string out = json(kept).dump();
        output_bytes += static_cast<std::int64_t>(out.size());
        if (rep == reps - 1) {
            std::uint32_t h = FNV_OFFSET;
            for (unsigned char b : out) h = (h ^ b) * FNV_PRIME;
            hash = h;
        }
    }

    std::cout << "records " << records_n << '\n';
    std::cout << "active " << active_n << '\n';
    std::cout << "score_sum " << score_sum << '\n';
    std::cout << "tags " << tags_n << '\n';
    std::cout << "history " << history_n << '\n';
    std::cout << "amount_sum " << amount_sum << '\n';
    std::cout << "output_bytes " << output_bytes << '\n';
    std::cout << "output_fnv1a " << hash << '\n';
}
