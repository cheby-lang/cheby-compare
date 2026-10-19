// n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).

let solarMass = 4.0 * Double.pi * Double.pi
let daysPerYear = 365.24
let dt = 0.01

struct Body {
  var x, y, z: Double
  var vx, vy, vz: Double
  var mass: Double
}

func planet(_ pos: [Double], _ vel: [Double], _ mass: Double) -> Body {
  Body(
    x: pos[0], y: pos[1], z: pos[2],
    vx: vel[0] * daysPerYear, vy: vel[1] * daysPerYear, vz: vel[2] * daysPerYear,
    mass: mass * solarMass)
}

func initialBodies() -> [Body] {
  let sun = Body(x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: solarMass)
  let jupiter = planet(
    [4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01],
    [1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05],
    9.54791938424326609e-04)
  let saturn = planet(
    [8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01],
    [-2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05],
    2.85885980666130812e-04)
  let uranus = planet(
    [1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01],
    [2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05],
    4.36624404335156298e-05)
  let neptune = planet(
    [1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01],
    [2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05],
    5.15138902046611451e-05)
  return [sun, jupiter, saturn, uranus, neptune]
}

func offsetMomentum(_ bodies: inout [Body]) {
  var px = 0.0
  var py = 0.0
  var pz = 0.0
  for b in bodies {
    px += b.vx * b.mass
    py += b.vy * b.mass
    pz += b.vz * b.mass
  }
  bodies[0].vx = -px / solarMass
  bodies[0].vy = -py / solarMass
  bodies[0].vz = -pz / solarMass
}

func energy(_ bodies: [Body]) -> Double {
  var e = 0.0
  for i in bodies.indices {
    let b = bodies[i]
    e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
    for j in (i + 1)..<bodies.count {
      let dx = b.x - bodies[j].x
      let dy = b.y - bodies[j].y
      let dz = b.z - bodies[j].z
      e -= b.mass * bodies[j].mass / (dx * dx + dy * dy + dz * dz).squareRoot()
    }
  }
  return e
}

func advance(_ bodies: inout [Body]) {
  let n = bodies.count
  for i in 0..<n {
    for j in (i + 1)..<n {
      let dx = bodies[i].x - bodies[j].x
      let dy = bodies[i].y - bodies[j].y
      let dz = bodies[i].z - bodies[j].z
      let d2 = dx * dx + dy * dy + dz * dz
      let mag = dt / (d2 * d2.squareRoot())
      let aMag = bodies[i].mass * mag
      let bMag = bodies[j].mass * mag
      bodies[i].vx -= dx * bMag
      bodies[i].vy -= dy * bMag
      bodies[i].vz -= dz * bMag
      bodies[j].vx += dx * aMag
      bodies[j].vy += dy * aMag
      bodies[j].vz += dz * aMag
    }
  }
  for i in 0..<n {
    bodies[i].x += dt * bodies[i].vx
    bodies[i].y += dt * bodies[i].vy
    bodies[i].z += dt * bodies[i].vz
  }
}

func scaled(_ e: Double) -> Int {
  Int((e * 1e9).rounded())
}

let steps = Int(CommandLine.arguments[1])!
var bodies = initialBodies()
offsetMomentum(&bodies)
print(scaled(energy(bodies)))
for _ in 0..<steps {
  advance(&bodies)
}
print(scaled(energy(bodies)))
