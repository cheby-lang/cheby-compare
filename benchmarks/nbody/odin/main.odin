// n-body: five bodies of the outer solar system under gravity, advanced in
// fixed steps. Prints the total energy before and after, as round(e * 10^9).
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"

PI :: 3.141592653589793
SOLAR_MASS :: 4.0 * PI * PI
DAYS_PER_YEAR :: 365.24
DT :: 0.01

Body :: struct {
	x, y, z, vx, vy, vz, mass: f64,
}

planet :: proc(pos, vel: [3]f64, mass: f64) -> Body {
	return Body {
		x = pos[0],
		y = pos[1],
		z = pos[2],
		vx = vel[0] * DAYS_PER_YEAR,
		vy = vel[1] * DAYS_PER_YEAR,
		vz = vel[2] * DAYS_PER_YEAR,
		mass = mass * SOLAR_MASS,
	}
}

initial_bodies :: proc() -> [5]Body {
	sun := Body{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS}
	jupiter := planet(
		{4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01},
		{1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05},
		9.54791938424326609e-04,
	)
	saturn := planet(
		{8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01},
		{-2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05},
		2.85885980666130812e-04,
	)
	uranus := planet(
		{1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01},
		{2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05},
		4.36624404335156298e-05,
	)
	neptune := planet(
		{1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01},
		{2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05},
		5.15138902046611451e-05,
	)
	return {sun, jupiter, saturn, uranus, neptune}
}

offset_momentum :: proc(bodies: []Body) {
	px, py, pz: f64
	for b in bodies {
		px += b.vx * b.mass
		py += b.vy * b.mass
		pz += b.vz * b.mass
	}
	bodies[0].vx = -px / SOLAR_MASS
	bodies[0].vy = -py / SOLAR_MASS
	bodies[0].vz = -pz / SOLAR_MASS
}

energy :: proc(bodies: []Body) -> f64 {
	e := 0.0
	for b, i in bodies {
		e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
		for c in bodies[i + 1:] {
			dx := b.x - c.x
			dy := b.y - c.y
			dz := b.z - c.z
			e -= b.mass * c.mass / math.sqrt(dx * dx + dy * dy + dz * dz)
		}
	}
	return e
}

advance :: proc(bodies: []Body) {
	for i in 0 ..< len(bodies) {
		a := &bodies[i]
		for j in i + 1 ..< len(bodies) {
			b := &bodies[j]
			dx := a.x - b.x
			dy := a.y - b.y
			dz := a.z - b.z
			d2 := dx * dx + dy * dy + dz * dz
			mag := DT / (d2 * math.sqrt(d2))
			a_mag := a.mass * mag
			b_mag := b.mass * mag
			a.vx -= dx * b_mag
			a.vy -= dy * b_mag
			a.vz -= dz * b_mag
			b.vx += dx * a_mag
			b.vy += dy * a_mag
			b.vz += dz * a_mag
		}
	}
	for &b in bodies {
		b.x += DT * b.vx
		b.y += DT * b.vy
		b.z += DT * b.vz
	}
}

scaled :: proc(e: f64) -> i64 {
	return i64(math.round(e * 1.0e9))
}

main :: proc() {
	if len(os.args) < 2 {
		os.exit(2)
	}
	steps, ok := strconv.parse_int(os.args[1])
	if !ok || steps < 0 {
		os.exit(2)
	}
	bodies := initial_bodies()
	offset_momentum(bodies[:])
	fmt.println(scaled(energy(bodies[:])))
	for _ in 0 ..< steps {
		advance(bodies[:])
	}
	fmt.println(scaled(energy(bodies[:])))
}
