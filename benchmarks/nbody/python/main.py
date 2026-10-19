"""n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.

Prints the total energy before and after, as round(e * 10^9).
"""

import math
import sys

PI = 3.141592653589793
SOLAR_MASS = 4.0 * PI * PI
DAYS_PER_YEAR = 365.24
DT = 0.01


class Body:
    __slots__ = ("x", "y", "z", "vx", "vy", "vz", "mass")

    def __init__(self, x, y, z, vx, vy, vz, mass):
        self.x = x
        self.y = y
        self.z = z
        self.vx = vx
        self.vy = vy
        self.vz = vz
        self.mass = mass


def planet(pos, vel, mass):
    return Body(
        pos[0],
        pos[1],
        pos[2],
        vel[0] * DAYS_PER_YEAR,
        vel[1] * DAYS_PER_YEAR,
        vel[2] * DAYS_PER_YEAR,
        mass * SOLAR_MASS,
    )


def initial_bodies():
    sun = Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS)
    jupiter = planet(
        (4.84143144246472090e00, -1.16032004402742839e00, -1.03622044471123109e-01),
        (1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05),
        9.54791938424326609e-04,
    )
    saturn = planet(
        (8.34336671824457987e00, 4.12479856412430479e00, -4.03523417114321381e-01),
        (-2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05),
        2.85885980666130812e-04,
    )
    uranus = planet(
        (1.28943695621391310e01, -1.51111514016986312e01, -2.23307578892655734e-01),
        (2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05),
        4.36624404335156298e-05,
    )
    neptune = planet(
        (1.53796971148509165e01, -2.59193146099879641e01, 1.79258772950371181e-01),
        (2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05),
        5.15138902046611451e-05,
    )
    return [sun, jupiter, saturn, uranus, neptune]


def offset_momentum(bodies):
    px = py = pz = 0.0
    for b in bodies:
        px += b.vx * b.mass
        py += b.vy * b.mass
        pz += b.vz * b.mass
    sun = bodies[0]
    sun.vx = -px / SOLAR_MASS
    sun.vy = -py / SOLAR_MASS
    sun.vz = -pz / SOLAR_MASS


def energy(bodies):
    e = 0.0
    for i, bi in enumerate(bodies):
        e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz)
        for bj in bodies[i + 1 :]:
            dx = bi.x - bj.x
            dy = bi.y - bj.y
            dz = bi.z - bj.z
            e -= bi.mass * bj.mass / math.sqrt(dx * dx + dy * dy + dz * dz)
    return e


def advance(pairs, bodies):
    for bi, bj in pairs:
        dx = bi.x - bj.x
        dy = bi.y - bj.y
        dz = bi.z - bj.z
        d2 = dx * dx + dy * dy + dz * dz
        mag = DT / (d2 * math.sqrt(d2))
        mi_mag = bi.mass * mag
        mj_mag = bj.mass * mag
        bi.vx -= dx * mj_mag
        bi.vy -= dy * mj_mag
        bi.vz -= dz * mj_mag
        bj.vx += dx * mi_mag
        bj.vy += dy * mi_mag
        bj.vz += dz * mi_mag
    for b in bodies:
        b.x += DT * b.vx
        b.y += DT * b.vy
        b.z += DT * b.vz


def scaled(e):
    """round(e * 10^9), halves away from zero (Python's round() goes to even)."""
    x = e * 1e9
    t = math.trunc(x)
    if abs(x - t) >= 0.5:
        t += 1 if x > 0 else -1
    return t


def main():
    steps = int(sys.argv[1])
    bodies = initial_bodies()
    offset_momentum(bodies)
    print(scaled(energy(bodies)))
    # The pairs (i, j) with i < j, in the order of the nested loops.
    pairs = [(bodies[i], bodies[j]) for i in range(5) for j in range(i + 1, 5)]
    for _ in range(steps):
        advance(pairs, bodies)
    print(scaled(energy(bodies)))


main()
