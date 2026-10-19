// Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.

#include <cstdint>
#include <iostream>
#include <string>

namespace {

constexpr int max_iter = 50;

// The number of iterations before the point (cr, ci) escapes, or max_iter.
int escape_time(double cr, double ci) {
    double zr = 0.0;
    double zi = 0.0;
    int i = 0;
    while (i < max_iter) {
        const double zr2 = zr * zr;
        const double zi2 = zi * zi;
        if (zr2 + zi2 > 4.0) {
            break;
        }
        zi = 2.0 * zr * zi + ci;
        zr = zr2 - zi2 + cr;
        ++i;
    }
    return i;
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main N\n";
        return 1;
    }
    const std::int64_t n = std::stoll(argv[1]);
    const double nf = static_cast<double>(n);
    std::int64_t inside = 0;
    std::int64_t iterations = 0;
    std::int64_t checksum = 0;
    for (std::int64_t y = 0; y < n; ++y) {
        const double ci = 2.0 * static_cast<double>(y) / nf - 1.0;
        for (std::int64_t x = 0; x < n; ++x) {
            const double cr = 2.0 * static_cast<double>(x) / nf - 1.5;
            const int i = escape_time(cr, ci);
            iterations += i;
            if (i == max_iter) {
                ++inside;
                checksum += y * n + x;
            }
        }
    }
    std::cout << "inside " << inside << '\n';
    std::cout << "iterations " << iterations << '\n';
    std::cout << "checksum " << checksum % (std::int64_t{1} << 32) << '\n';
}
