// Spectral norm: the benchmarks-game power method on the matrix
// A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

namespace {

// The entry A(i, j) of the matrix.
double entry(std::size_t i, std::size_t j) {
    return 1.0 / static_cast<double>((i + j) * (i + j + 1) / 2 + i + 1);
}

// Writes A times `x` into `out`.
void times_a(const std::vector<double>& x, std::vector<double>& out) {
    for (std::size_t i = 0; i < out.size(); ++i) {
        double sum = 0.0;
        for (std::size_t j = 0; j < x.size(); ++j) {
            sum += entry(i, j) * x[j];
        }
        out[i] = sum;
    }
}

// Writes A transposed times `x` into `out`.
void times_at(const std::vector<double>& x, std::vector<double>& out) {
    for (std::size_t i = 0; i < out.size(); ++i) {
        double sum = 0.0;
        for (std::size_t j = 0; j < x.size(); ++j) {
            sum += entry(j, i) * x[j];
        }
        out[i] = sum;
    }
}

// Writes A transposed times A times `x` into `out`, using `tmp`.
void times_ata(const std::vector<double>& x, std::vector<double>& tmp, std::vector<double>& out) {
    times_a(x, tmp);
    times_at(tmp, out);
}

double dot(const std::vector<double>& x, const std::vector<double>& y) {
    double sum = 0.0;
    for (std::size_t i = 0; i < x.size(); ++i) {
        sum += x[i] * y[i];
    }
    return sum;
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main N\n";
        return 1;
    }
    const auto n = static_cast<std::size_t>(std::stoull(argv[1]));
    std::vector<double> u(n, 1.0);
    std::vector<double> v(n, 0.0);
    std::vector<double> tmp(n, 0.0);
    for (int round = 0; round < 10; ++round) {
        times_ata(u, tmp, v);
        times_ata(v, tmp, u);
    }
    const double vv = dot(v, v);
    const std::int64_t result = vv == 0.0 ? 0 : std::llround(std::sqrt(dot(u, v) / vv) * 1.0e9);
    std::cout << result << '\n';
}
