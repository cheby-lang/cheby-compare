// n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).
package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
)

const (
	solarMass   = 4.0 * math.Pi * math.Pi
	daysPerYear = 365.24
	dt          = 0.01
)

// Body is one body's position, velocity and mass.
type Body struct {
	x, y, z, vx, vy, vz, mass float64
}

func planet(x, y, z, vx, vy, vz, mass float64) Body {
	return Body{
		x: x, y: y, z: z,
		vx: vx * daysPerYear, vy: vy * daysPerYear, vz: vz * daysPerYear,
		mass: mass * solarMass,
	}
}

func initialBodies() []Body {
	return []Body{
		{mass: solarMass},
		planet( // Jupiter
			4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
			1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
			9.54791938424326609e-04),
		planet( // Saturn
			8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
			-2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
			2.85885980666130812e-04),
		planet( // Uranus
			1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
			2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
			4.36624404335156298e-05),
		planet( // Neptune
			1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
			2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
			5.15138902046611451e-05),
	}
}

func offsetMomentum(bodies []Body) {
	var px, py, pz float64
	for _, b := range bodies {
		px += b.vx * b.mass
		py += b.vy * b.mass
		pz += b.vz * b.mass
	}
	bodies[0].vx = -px / solarMass
	bodies[0].vy = -py / solarMass
	bodies[0].vz = -pz / solarMass
}

func energy(bodies []Body) float64 {
	e := 0.0
	for i, b := range bodies {
		e += 0.5 * b.mass * (b.vx*b.vx + b.vy*b.vy + b.vz*b.vz)
		for j := i + 1; j < len(bodies); j++ {
			dx := b.x - bodies[j].x
			dy := b.y - bodies[j].y
			dz := b.z - bodies[j].z
			e -= b.mass * bodies[j].mass / math.Sqrt(dx*dx+dy*dy+dz*dz)
		}
	}
	return e
}

func advance(bodies []Body) {
	for i := range bodies {
		a := &bodies[i]
		for j := i + 1; j < len(bodies); j++ {
			b := &bodies[j]
			dx := a.x - b.x
			dy := a.y - b.y
			dz := a.z - b.z
			d2 := dx*dx + dy*dy + dz*dz
			mag := dt / (d2 * math.Sqrt(d2))
			aMag := a.mass * mag
			bMag := b.mass * mag
			a.vx -= dx * bMag
			a.vy -= dy * bMag
			a.vz -= dz * bMag
			b.vx += dx * aMag
			b.vy += dy * aMag
			b.vz += dz * aMag
		}
	}
	for i := range bodies {
		b := &bodies[i]
		b.x += dt * b.vx
		b.y += dt * b.vy
		b.z += dt * b.vz
	}
}

func scaled(e float64) int64 {
	return int64(math.Round(e * 1e9))
}

func main() {
	steps, err := strconv.Atoi(os.Args[1])
	if err != nil || steps < 0 {
		fmt.Fprintln(os.Stderr, "usage: main <steps>")
		os.Exit(2)
	}
	bodies := initialBodies()
	offsetMomentum(bodies)
	fmt.Println(scaled(energy(bodies)))
	for range steps {
		advance(bodies)
	}
	fmt.Println(scaled(energy(bodies)))
}
