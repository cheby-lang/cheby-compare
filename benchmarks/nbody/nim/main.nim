# nbody: the Sun and the four giant planets under Newtonian gravity, advanced in fixed steps.
# Prints the total energy before and after, as round(e * 10^9).

import std/[os, strutils, math]

const
  solarMass = 4.0 * PI * PI
  daysPerYear = 365.24
  dt = 0.01

type Body = object
  x, y, z, vx, vy, vz, mass: float

proc planet(x, y, z, vx, vy, vz, mass: float): Body =
  Body(x: x, y: y, z: z,
       vx: vx * daysPerYear, vy: vy * daysPerYear, vz: vz * daysPerYear,
       mass: mass * solarMass)

proc initialBodies(): array[5, Body] =
  [
    Body(x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: solarMass),
    planet( # Jupiter
      4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
      1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
      9.54791938424326609e-04),
    planet( # Saturn
      8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
      -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
      2.85885980666130812e-04),
    planet( # Uranus
      1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
      2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
      4.36624404335156298e-05),
    planet( # Neptune
      1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
      2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
      5.15138902046611451e-05),
  ]

proc offsetMomentum(bodies: var openArray[Body]) =
  var px, py, pz = 0.0
  for b in bodies:
    px += b.vx * b.mass
    py += b.vy * b.mass
    pz += b.vz * b.mass
  bodies[0].vx = -px / solarMass
  bodies[0].vy = -py / solarMass
  bodies[0].vz = -pz / solarMass

proc energy(bodies: openArray[Body]): float =
  for i in 0 ..< bodies.len:
    let b = bodies[i]
    result += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
    for j in i + 1 ..< bodies.len:
      let dx = b.x - bodies[j].x
      let dy = b.y - bodies[j].y
      let dz = b.z - bodies[j].z
      result -= b.mass * bodies[j].mass / sqrt(dx * dx + dy * dy + dz * dz)

proc advance(bodies: var openArray[Body]) =
  for i in 0 ..< bodies.len:
    for j in i + 1 ..< bodies.len:
      let dx = bodies[i].x - bodies[j].x
      let dy = bodies[i].y - bodies[j].y
      let dz = bodies[i].z - bodies[j].z
      let d2 = dx * dx + dy * dy + dz * dz
      let mag = dt / (d2 * sqrt(d2))
      let aMag = bodies[i].mass * mag
      let bMag = bodies[j].mass * mag
      bodies[i].vx -= dx * bMag
      bodies[i].vy -= dy * bMag
      bodies[i].vz -= dz * bMag
      bodies[j].vx += dx * aMag
      bodies[j].vy += dy * aMag
      bodies[j].vz += dz * aMag
  for b in bodies.mitems:
    b.x += dt * b.vx
    b.y += dt * b.vy
    b.z += dt * b.vz

proc scaled(e: float): int64 = int64(round(e * 1.0e9))

proc main() =
  let steps = parseInt(paramStr(1))
  var bodies = initialBodies()
  offsetMomentum(bodies)
  echo scaled(energy(bodies))
  for _ in 1 .. steps:
    advance(bodies)
  echo scaled(energy(bodies))

main()
