// n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).

#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <numbers>
#include <string>

namespace {

constexpr double solar_mass = 4.0 * std::numbers::pi * std::numbers::pi;
constexpr double days_per_year = 365.24;
constexpr double dt = 0.01;

struct Body {
    double x, y, z, vx, vy, vz, mass;
};

constexpr Body planet(double x, double y, double z, double vx, double vy, double vz,
                      double mass) {
    return {x,
            y,
            z,
            vx * days_per_year,
            vy * days_per_year,
            vz * days_per_year,
            mass * solar_mass};
}

using Bodies = std::array<Body, 5>;

Bodies initial_bodies() {
    return {{
        // Sun
        {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solar_mass},
        // Jupiter
        planet(4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
               1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
               9.54791938424326609e-04),
        // Saturn
        planet(8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
               -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
               2.85885980666130812e-04),
        // Uranus
        planet(1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
               2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
               4.36624404335156298e-05),
        // Neptune
        planet(1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
               2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
               5.15138902046611451e-05),
    }};
}

void offset_momentum(Bodies& bodies) {
    double px = 0.0, py = 0.0, pz = 0.0;
    for (const Body& b : bodies) {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    bodies[0].vx = -px / solar_mass;
    bodies[0].vy = -py / solar_mass;
    bodies[0].vz = -pz / solar_mass;
}

double energy(const Bodies& bodies) {
    double e = 0.0;
    for (std::size_t i = 0; i < bodies.size(); ++i) {
        const Body& a = bodies[i];
        e += 0.5 * a.mass * (a.vx * a.vx + a.vy * a.vy + a.vz * a.vz);
        for (std::size_t j = i + 1; j < bodies.size(); ++j) {
            const Body& b = bodies[j];
            const double dx = a.x - b.x;
            const double dy = a.y - b.y;
            const double dz = a.z - b.z;
            e -= a.mass * b.mass / std::sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

void advance(Bodies& bodies) {
    for (std::size_t i = 0; i < bodies.size(); ++i) {
        Body& a = bodies[i];
        for (std::size_t j = i + 1; j < bodies.size(); ++j) {
            Body& b = bodies[j];
            const double dx = a.x - b.x;
            const double dy = a.y - b.y;
            const double dz = a.z - b.z;
            const double d2 = dx * dx + dy * dy + dz * dz;
            const double mag = dt / (d2 * std::sqrt(d2));
            const double a_mag = a.mass * mag;
            const double b_mag = b.mass * mag;
            a.vx -= dx * b_mag;
            a.vy -= dy * b_mag;
            a.vz -= dz * b_mag;
            b.vx += dx * a_mag;
            b.vy += dy * a_mag;
            b.vz += dz * a_mag;
        }
    }
    for (Body& b : bodies) {
        b.x += dt * b.vx;
        b.y += dt * b.vy;
        b.z += dt * b.vz;
    }
}

std::int64_t scaled(double e) { return std::llround(e * 1.0e9); }

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main <steps>\n";
        return 1;
    }
    const std::int64_t steps = std::stoll(argv[1]);
    Bodies bodies = initial_bodies();
    offset_momentum(bodies);
    std::cout << scaled(energy(bodies)) << '\n';
    for (std::int64_t step = 0; step < steps; ++step) {
        advance(bodies);
    }
    std::cout << scaled(energy(bodies)) << '\n';
}
